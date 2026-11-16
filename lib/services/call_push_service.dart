import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/active_call_manager.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../main.dart';
import '../screens/common/direct_chat_screen.dart';
import 'api_service.dart';

const FirebaseOptions kAndroidFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDpiYOYzu7NGZKQHP1qLlRkkM9CcXvZ-eE',
  appId: '1:972145849986:android:7e74ce33b40b3e98aea69b',
  messagingSenderId: '972145849986',
  projectId: 'feelback-536d4',
  storageBucket: 'feelback-536d4.firebasestorage.app',
);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await CallPushService.ensureFirebaseInitialized();
  await CallPushService.handleRemoteMessageData(message.data, isBackgroundIsolate: true);
}

@pragma('vm:entry-point')
Future<void> callkitBackgroundHandler(CallEvent event) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (event is CallEventActionCallDecline) {
    final sessionId = CallPushService._extractSessionId(event.callKitParams);
    if (sessionId.isEmpty) return;
    try {
      const storage = FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      final jwt = await storage.read(key: 'talkstrangers_access_token');
      if (jwt != null && jwt.isNotEmpty) {
        final client = ApiClient()..token = jwt;
        await ApiService(client)
            .rejectSession(sessionId, 'Listener declined')
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    try {
      await FlutterCallkitIncoming.endCall(event.callKitParams.id);
    } catch (_) {}
  }
}

class CallPushService {
  CallPushService._();
  static final CallPushService instance = CallPushService._();

  static const String _alertChannelId = 'feelback_alerts';
  static const String _alertChannelName = 'FeelBack Alerts';
  static const String _ongoingCallChannelId = 'feelback_ongoing_call';
  static const String _ongoingCallChannelName = 'Ongoing Call';
  static const int _ongoingCallNotificationId = 99998;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  ApiService? _api;
  String? _lastUploadedToken;
  bool _initialized = false;
  bool _localNotificationsReady = false;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<CallEvent?>? _callKitSub;

  VoidCallback? onForegroundIncomingCall;
  VoidCallback? onAlertNotificationReceived;

  final Set<String> _handledInAppCallIds = <String>{};
  final Set<String> _inFlightAcceptIds = <String>{};
  CallKitParams? _pendingAcceptedCallKit;

  static Future<void> ensureFirebaseInitialized() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (Firebase.apps.isNotEmpty) return;
    try {
      await Firebase.initializeApp(options: kAndroidFirebaseOptions);
    } catch (e) {
      debugPrint('[CallPushService] Firebase init warning: $e');
    }
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _initialized = true;

    await ensureFirebaseInitialized();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _initLocalNotifications();

    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundRemoteMessage);
    _onOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onAlertNotificationReceived?.call();
      onForegroundIncomingCall?.call();
      final data = message.data;
      if ('${data['type'] ?? ''}'.toUpperCase() == 'DIRECT_CHAT_MESSAGE') {
        final threadId = data['threadId']?.toString();
        final senderId = data['senderId']?.toString();
        final senderName = data['senderName']?.toString() ?? 'User';
        FeelAgainApp.navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              threadId: threadId,
              otherUserId: senderId,
              otherUserName: senderName,
            ),
          ),
        );
      }
    });

    _callKitSub = FlutterCallkitIncoming.onEvent.listen(
      _handleCallKitEvent,
      onError: (e) => debugPrint('[CallPushService] CallKit event error: $e'),
    );

    try {
      await FlutterCallkitIncoming.onBackgroundMessage(callkitBackgroundHandler);
    } catch (e) {
      debugPrint('[CallPushService] CallKit background registration note: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    if (_localNotificationsReady) return;
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.startsWith('DIRECT_CHAT:')) {
            final parts = payload.substring('DIRECT_CHAT:'.length).split('||');
            final threadId = parts[0];
            final senderName = parts.length > 1 ? parts[1] : 'User';
            final senderId = parts.length > 2 ? parts[2] : null;
            FeelAgainApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => DirectChatScreen(
                  threadId: threadId.isNotEmpty ? threadId : null,
                  otherUserId: senderId,
                  otherUserName: senderName,
                ),
              ),
            );
          }
        },
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _alertChannelId,
          _alertChannelName,
          description: 'Incoming nudges, listener availability alerts, and session updates.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _ongoingCallChannelId,
          _ongoingCallChannelName,
          description: 'Active call audio and connection notification.',
          importance: Importance.max,
          playSound: false,
          enableVibration: false,
        ),
      );
      _localNotificationsReady = true;
    } catch (e) {
      debugPrint('[CallPushService] Local notifications init warning: $e');
    }
  }

  Future<void> onUserAuthenticated(ApiService api) async {
    _api = api;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await initialize();
    await _requestPermissionsAndRegisterToken(api);

    // Handle any CallKit accept that fired while bootstrap was still completing
    if (_pendingAcceptedCallKit != null) {
      final pending = _pendingAcceptedCallKit!;
      _pendingAcceptedCallKit = null;
      await _processAcceptedCallKit(pending, api);
    }

    // Handle cold-start CallKit accept or lingering active CallKit notifications
    await syncPendingCallKitAction(api);

    try {
      final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMsg != null) {
        onAlertNotificationReceived?.call();
        onForegroundIncomingCall?.call();
        final data = initialMsg.data;
        if ('${data['type'] ?? ''}'.toUpperCase() == 'DIRECT_CHAT_MESSAGE') {
          final threadId = data['threadId']?.toString();
          final senderId = data['senderId']?.toString();
          final senderName = data['senderName']?.toString() ?? 'User';
          Future.delayed(const Duration(milliseconds: 600), () {
            FeelAgainApp.navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (_) => DirectChatScreen(
                  threadId: threadId,
                  otherUserId: senderId,
                  otherUserName: senderName,
                ),
              ),
            );
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _requestPermissionsAndRegisterToken(ApiService api) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    try {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}

    try {
      final canFullScreen = await canUseFullScreenCalls();
      if (!canFullScreen) {
        await requestFullScreenCallsPermission();
      }
    } catch (_) {}

    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _uploadTokenIfNeeded(api, token);
      }
    } catch (e) {
      debugPrint('[CallPushService] Failed getting FCM token: $e');
    }

    await _tokenRefreshSub?.cancel();
    // ignore: deprecated_member_use
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final activeApi = _api;
      if (activeApi != null && newToken.isNotEmpty) {
        await _uploadTokenIfNeeded(activeApi, newToken);
      }
    });
  }

  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onOpenedAppSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _callKitSub?.cancel();
    _onMessageSub = null;
    _onOpenedAppSub = null;
    _tokenRefreshSub = null;
    _callKitSub = null;
    _initialized = false;
  }

  Future<void> _uploadTokenIfNeeded(ApiService api, String token) async {
    if (_lastUploadedToken == token) return;
    try {
      await api.updateFcmToken(token).timeout(AppConfig.networkTimeout);
      _lastUploadedToken = token;
      debugPrint('[CallPushService] Registered FCM token with backend');
    } catch (e) {
      debugPrint('[CallPushService] Failed uploading FCM token: $e');
    }
  }

  Future<void> onLogout(ApiService? api) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _api = null;
    _lastUploadedToken = null;
    _pendingAcceptedCallKit = null;
    _handledInAppCallIds.clear();

    if (api != null) {
      try {
        await api.clearFcmToken().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
    }
  }

  void markSessionHandledInApp(String sessionId) {
    if (sessionId.isEmpty) return;
    _handledInAppCallIds.add(sessionId);
  }

  void clearSessionHandledInApp(String sessionId) {
    _handledInAppCallIds.remove(sessionId);
  }

  Future<void> dismissCallNotification(String sessionId) async {
    if (sessionId.isEmpty || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await FlutterCallkitIncoming.endCall(sessionId);
    } catch (_) {}
  }

  Future<bool> canUseFullScreenCalls() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await FlutterCallkitIncoming.canUseFullScreenIntent();
    } catch (_) {
      return true;
    }
  }

  Future<void> requestFullScreenCallsPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {}
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final data = message.data;
    final type = '${data['type'] ?? ''}'.toUpperCase();

    if (type == 'INCOMING_CALL') {
      final sessionId = '${data['sessionId'] ?? ''}';
      if (sessionId.isEmpty) return;
      if (ActiveCallManager.instance.activeSession?.id == sessionId ||
          _handledInAppCallIds.contains(sessionId)) {
        return;
      }

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycle == AppLifecycleState.resumed;
      if (isForeground && onForegroundIncomingCall != null) {
        // Trigger immediate in-app poll so the branded IncomingCallOverlay pops instantly.
        onForegroundIncomingCall!();
        return;
      }

      await handleRemoteMessageData(data, isBackgroundIsolate: false);
      return;
    }

    if (type == 'CALL_ENDED') {
      await handleRemoteMessageData(data, isBackgroundIsolate: false);
      return;
    }

    if (type == 'DIRECT_CHAT_MESSAGE') {
      onAlertNotificationReceived?.call();
      final threadId = data['threadId']?.toString() ?? '';
      final senderName = data['senderName']?.toString() ?? 'New Message';
      final senderId = data['senderId']?.toString() ?? '';
      final text = data['text']?.toString() ?? (message.notification?.body ?? 'Sent you a message');

      await _initLocalNotifications();
      try {
        await _localNotifications.show(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: senderName,
          body: text,
          payload: 'DIRECT_CHAT:$threadId||$senderName||$senderId',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _alertChannelId,
              _alertChannelName,
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[CallPushService] Failed showing direct chat local notification: $e');
      }
      return;
    }

    onAlertNotificationReceived?.call();

    // Display foreground tray notification for non-call alerts (e.g., CALLER_NUDGE, LISTENER_ONLINE).
    final notification = message.notification;
    if (notification != null && (notification.title != null || notification.body != null)) {
      await _initLocalNotifications();
      try {
        await _localNotifications.show(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          title: notification.title ?? 'FeelBack',
          body: notification.body ?? '',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _alertChannelId,
              _alertChannelName,
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[CallPushService] Failed showing local notification: $e');
      }
    }
  }

  static Future<void> handleRemoteMessageData(
    Map<String, dynamic> data, {
    required bool isBackgroundIsolate,
  }) async {
    final type = '${data['type'] ?? ''}'.toUpperCase();
    final sessionId = '${data['sessionId'] ?? ''}';

    if (type == 'CALL_ENDED') {
      try {
        if (sessionId.isNotEmpty) {
          await FlutterCallkitIncoming.endCall(sessionId);
        } else {
          await FlutterCallkitIncoming.endAllCalls();
        }
      } catch (e) {
        debugPrint('[CallPushService] Error dismissing CallKit on CALL_ENDED: $e');
      }
      return;
    }

    if (type != 'INCOMING_CALL' || sessionId.isEmpty) return;

    // Ignore stale/delayed FCM messages whose ring window already expired.
    int durationMs = 45000;
    final expiresRaw = '${data['expiresAt'] ?? ''}'.trim();
    if (expiresRaw.isNotEmpty) {
      final expires = DateTime.tryParse(expiresRaw);
      if (expires != null) {
        final remaining = expires.difference(DateTime.now()).inMilliseconds;
        if (remaining < -2000) {
          debugPrint('[CallPushService] Skipping expired INCOMING_CALL push for $sessionId');
          return;
        }
        durationMs = remaining.clamp(5000, 90000);
      }
    }

    final callType = '${data['callType'] ?? 'AUDIO_CALL'}'.toUpperCase();
    final isCallback = '${data['isCallback'] ?? 'false'}'.toLowerCase() == 'true';
    final callerName = ('${data['callerName'] ?? ''}'.trim().isNotEmpty)
        ? '${data['callerName']}'.trim()
        : (isCallback ? 'Listener Callback' : 'Anonymous Caller');
    final avatar = '${data['callerAvatar'] ?? ''}'.trim();

    final handleLabel = switch (callType) {
      'VIDEO_CALL' => isCallback ? 'Incoming Video Callback' : 'Video Call',
      'CHAT' => isCallback ? 'Incoming Chat Callback' : 'Chat Request',
      _ => isCallback ? 'Incoming Voice Callback' : 'Audio Call',
    };

    final acceptLabel = callType == 'CHAT' ? 'Open Chat' : 'Accept';

    final params = CallKitParams(
      id: sessionId,
      nameCaller: callerName,
      appName: 'FeelBack',
      avatar: avatar.isNotEmpty ? avatar : null,
      handle: handleLabel,
      type: callType == 'VIDEO_CALL' ? 1 : 0,
      duration: durationMs,
      extra: <String, dynamic>{...data, 'sessionId': sessionId},
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: callType == 'CHAT' ? 'Missed chat request' : 'Missed call from $callerName',
      ),
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1E1B4B',
        actionColor: '#10B981',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowFullLockedScreen: true,
        isImportant: true,
        isFullScreen: true,
        isShowCallID: false,
        textAccept: acceptLabel,
        textDecline: 'Decline',
      ),
      ios: IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: callType == 'VIDEO_CALL',
        ringtonePath: 'system_ringtone_default',
      ),
    );

    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      debugPrint('[CallPushService] showCallkitIncoming failed: $e');
    }
  }

  Future<void> _handleCallKitEvent(CallEvent? event) async {
    if (event == null) return;
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        final api = _api;
        if (api == null) {
          _pendingAcceptedCallKit = callKitParams;
          return;
        }
        await _processAcceptedCallKit(callKitParams, api);
      case CallEventActionCallDecline(:final callKitParams):
        await _processDeclinedCallKit(callKitParams);
      case CallEventActionCallTimeout(:final id):
        _handledInAppCallIds.remove(id);
      case CallEventActionCallEnded(:final callKitParams):
        _handledInAppCallIds.remove(_extractSessionId(callKitParams));
      default:
        break;
    }
  }

  Future<void> syncPendingCallKitAction(ApiService api) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        final sessionId = _extractSessionId(call);
        if (sessionId.isEmpty) continue;

        final session = await api.session(sessionId);
        if (session.ended) {
          await dismissCallNotification(call.id);
          continue;
        }

        if (call.isAccepted ||
            session.status == 'ACCEPTED' ||
            session.status == 'CONNECTING' ||
            session.status == 'CONNECTED') {
          await _processAcceptedCallKit(call, api);
        }
      }
    } catch (e) {
      debugPrint('[CallPushService] syncPendingCallKitAction error: $e');
    }
  }

  Future<void> _processAcceptedCallKit(CallKitParams params, ApiService api) async {
    final sessionId = _extractSessionId(params);
    if (sessionId.isEmpty || _inFlightAcceptIds.contains(sessionId)) return;

    _inFlightAcceptIds.add(sessionId);
    _handledInAppCallIds.add(sessionId);
    try {
      final current = await api.session(sessionId);
      if (current.ended) {
        await dismissCallNotification(params.id);
        return;
      }

      final isCallback = current.reference.startsWith('CB-') ||
          '${params.extra?['isCallback'] ?? ''}'.toLowerCase() == 'true';

      final sessionToJoin = current.status == 'REQUESTED'
          ? await api.acceptSession(sessionId)
          : current;

      if (ActiveCallManager.instance.activeSession?.id != sessionToJoin.id) {
        ActiveCallManager.instance.startCall(sessionToJoin, callerSide: isCallback);
      }

      await dismissCallNotification(params.id);
    } catch (e) {
      debugPrint('[CallPushService] Failed accepting CallKit call $sessionId: $e');
      await dismissCallNotification(params.id);
    } finally {
      _inFlightAcceptIds.remove(sessionId);
    }
  }

  Future<void> _processDeclinedCallKit(CallKitParams params) async {
    final sessionId = _extractSessionId(params);
    if (sessionId.isEmpty) return;

    try {
      final api = _api;
      if (api != null) {
        await api.rejectSession(sessionId, 'Listener declined');
      } else {
        const storage = FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );
        final jwt = await storage.read(key: 'talkstrangers_access_token');
        if (jwt != null && jwt.isNotEmpty) {
          final client = ApiClient()..token = jwt;
          await ApiService(client).rejectSession(sessionId, 'Listener declined');
        }
      }
    } catch (e) {
      debugPrint('[CallPushService] Failed rejecting CallKit call $sessionId: $e');
    } finally {
      await dismissCallNotification(params.id);
    }
  }

  static String _extractSessionId(CallKitParams params) {
    final extraId = '${params.extra?['sessionId'] ?? ''}'.trim();
    if (extraId.isNotEmpty) return extraId;
    return params.id.trim();
  }

  Future<void> showOngoingCallNotification({
    required String peerName,
    required bool isVideo,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await initialize();
      final typeLabel = isVideo ? 'Video Call' : 'Audio Call';
      final androidDetails = AndroidNotificationDetails(
        _ongoingCallChannelId,
        _ongoingCallChannelName,
        channelDescription: 'Active call audio and connection notification.',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true,
        autoCancel: false,
        showWhen: true,
        usesChronometer: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        icon: '@mipmap/ic_launcher',
      );
      final details = NotificationDetails(android: androidDetails);
      await _localNotifications.show(
        id: _ongoingCallNotificationId,
        title: 'Active $typeLabel with $peerName',
        body: 'Call in progress • Tap to return to conversation',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[CallPushService] Ongoing notification warning: $e');
    }
  }

  Future<void> dismissOngoingCallNotification() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _localNotifications.cancel(id: _ongoingCallNotificationId);
    } catch (_) {}
  }
}

