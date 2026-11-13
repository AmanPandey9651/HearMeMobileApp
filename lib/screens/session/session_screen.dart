import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/android_voice_fx.dart';
import '../../services/api_service.dart';
import '../../services/call_recording_service.dart';
import '../../widgets/call_pulse_avatar.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/in_call_mini_games.dart';
import '../../widgets/in_call_gifting_sheet.dart';
import '../caller/wallet_screen.dart';
import '../../widgets/video_privacy_filter.dart';
import '../../widgets/nudity_guard_overlay.dart';
import '../../services/in_call_voice_safety_service.dart';

class SessionScreen extends StatefulWidget {
  final InstantSessionModel initialSession;
  final bool callerSide;
  final bool isHostedInGlobalManager;

  const SessionScreen({
    super.key,
    required this.initialSession,
    required this.callerSide,
    this.isHostedInGlobalManager = false,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late InstantSessionModel session = widget.initialSession;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

late final Future<void> _renderersReady;
  final voiceFx = AndroidVoiceFx();
  final _privacyAlerts = PrivacyAlertService();
  final gameSignal = ValueNotifier<Map<String, dynamic>?>(null);
  final messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool isPeerTyping = false;
  Timer? _peerTypingTimer;
  Timer? _myTypingTimer;
  bool _isMyTypingActive = false;

  void _startRingtone() {
    try {
      FlutterRingtonePlayer().playRingtone(
        volume: 0.8,
        looping: true,
        asAlarm: false,
      );
    } catch (_) {}
  }

  void _stopRingtone() {
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
  }
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  RTCPeerConnection? pc;
  RTCDataChannel? voiceChannel;
  MediaStream? localStream, remoteStream;
  Timer? sessionPoll, signalPoll, heartbeat, clock, messagePoll, reconnectTimer, _offerWatchdogTimer;
  int seconds = 0, signalSince = 0, reconnectSeconds = 30, ringRemaining = 45, elapsedRinging = 1;
  bool joining = false, mic = true, camera = true, speaker = true, ending = false;
  bool reconnecting = false, gameSheetOpen = false, registeredActiveSession = false, everLive = false;
  bool peerVoiceFxCapable = false, nativeVoiceFxActive = false;
  final queuedCandidates = <Map<String, dynamic>>[];
  Map<String, dynamic>? pendingOffer, pendingAnswer;
  RTCSessionDescription? _lastLocalDesc;

  Future<RTCSessionDescription?> _safeGetLocalDescription(RTCPeerConnection peer) async {
    if (_lastLocalDesc != null) return _lastLocalDesc;
    try {
      return await peer.getLocalDescription();
    } catch (_) {
      return null;
    }
  }
  List<dynamic> messages = [];
  String? banner;
  String activeVoiceFilter = AndroidVoiceFx.normal;
  String peerVoiceFilter = AndroidVoiceFx.normal;
  String activeVideoFilter = VideoPrivacyFilter.none;
  String peerVideoFilter = VideoPrivacyFilter.none;
  bool isNudityBlurred = false;
  String? nuditySource;
  bool isNudityAllowed = false;
  bool _nudityCooldownActive = false;
  Timer? _nudityCooldownTimer;
  final String _clientId = '${DateTime.now().microsecondsSinceEpoch}_${(1000 + DateTime.now().millisecond * 7 % 9000)}';

  // WhatsApp-style video overlay controls visibility & 5-second auto-hide timer
  bool _areVideoControlsVisible = true;
  Timer? _videoControlsTimer;

  void _resetVideoControlsTimer() {
    _videoControlsTimer?.cancel();
    if (_areVideoControlsVisible) {
      _videoControlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _areVideoControlsVisible) {
          setState(() {
            _areVideoControlsVisible = false;
          });
        }
      });
    }
  }

  void _toggleVideoControls() {
    setState(() {
      _areVideoControlsVisible = !_areVideoControlsVisible;
    });
    if (_areVideoControlsVisible) {
      _resetVideoControlsTimer();
    } else {
      _videoControlsTimer?.cancel();
    }
  }

  // Live money and balance tracking (real-time decreasing for caller, increasing for listener)
  double? _callerInitialBalance;
  double _callerGiftsSpent = 0.0;
  double _listenerGiftEarnings = 0.0;

  double get _effectiveRatePerMinute => session.ratePerMinute > 0 ? session.ratePerMinute : 10.0;

  double get _currentLiveCost {
    if (seconds < 5) return 0.0;
    return (seconds / 60.0) * _effectiveRatePerMinute;
  }

  double get _callerRemainingBalance {
    final initBal = _callerInitialBalance ??
        (session.maxAllowedSeconds > 0
            ? (session.maxAllowedSeconds / 60.0) * _effectiveRatePerMinute
            : 0.0);
    final rem = initBal - _currentLiveCost - _callerGiftsSpent;
    return rem > 0 ? rem : 0.0;
  }

  double get _listenerTotalEarnings {
    final callEarn = seconds < 5 ? 0.0 : ((seconds / 60.0) * _effectiveRatePerMinute * 0.80);
    return callEarn + _listenerGiftEarnings;
  }

  Future<void> _sendSignal(Map<String, dynamic> data) async {
    try {
      final payload = <String, dynamic>{
        ...data,
        'senderRole': widget.callerSide ? 'caller' : 'listener',
        'senderClientId': _clientId,
      };
      await _api.sendSignal(session.id, payload);
    } catch (_) {}
  }

  void _toggleNudityPermission({bool? forcedVal}) {
    if (!mounted) return;
    final nextVal = forcedVal ?? !isNudityAllowed;
    setState(() {
      isNudityAllowed = nextVal;
      if (nextVal) {
        isNudityBlurred = false;
        nuditySource = null;
        banner = '🔞 Nudity Mode ON — nudity allowed from both sides';
      } else {
        banner = '🛡️ Nudity protection re-enabled';
      }
    });
    _sendSignal({
      'type': 'NUDITY_PERMISSION_TOGGLED',
      'allowed': nextVal,
    });
  }

  void _dismissNudityBlur() {
    if (!mounted) return;
    setState(() {
      isNudityBlurred = false;
      nuditySource = null;
      _nudityCooldownActive = true;
    });
    _nudityCooldownTimer?.cancel();
    _nudityCooldownTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _nudityCooldownActive = false);
      }
    });
    _sendSignal({
      'type': 'NUDITY_ACKNOWLEDGED',
    });
  }

  DateTime? _lastNudityReportTime;

  Future<String?> _captureUnblurredSnapshot({String? source}) async {
    try {
      final isLocal = (source == 'local' || (source == 'user' && widget.callerSide) || (source == 'listener' && !widget.callerSide));
      final stream = isLocal ? localStream : (remoteStream ?? localStream);
      final videoTracks = stream?.getVideoTracks() ?? <MediaStreamTrack>[];
      if (videoTracks.isEmpty) return null;
      final track = videoTracks.first;
      final byteBuffer = await track.captureFrame();
      final bytes = byteBuffer.asUint8List();
      if (bytes.isEmpty) return null;
      final base64Str = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64Str';
    } catch (e) {
      debugPrint('[NudityModeration] Silent snapshot capture skipped or failed: $e');
      return null;
    }
  }

  void _reportNudityIncidentSilently({String? source}) {
    final now = DateTime.now();
    if (_lastNudityReportTime != null &&
        now.difference(_lastNudityReportTime!).inSeconds < 15) {
      return;
    }
    _lastNudityReportTime = now;

    // Capture unblurred frame thumbnail silently and send to backend for admin inspection
    _captureUnblurredSnapshot(source: source).then((snapshot) {
            final isOffenderLocal = (source == 'local' || (source == 'user' && widget.callerSide) || (source == 'listener' && !widget.callerSide));
      final offenderRole = isOffenderLocal
          ? (widget.callerSide ? 'USER' : 'LISTENER')
          : (widget.callerSide ? 'LISTENER' : 'USER');
      final offenderName = isOffenderLocal
          ? (widget.callerSide ? session.callerNickname : session.listenerName)
          : (widget.callerSide ? session.listenerName : session.callerNickname);
      final offenderId = isOffenderLocal
          ? (widget.callerSide ? session.callerId : session.listenerId)
          : (widget.callerSide ? session.listenerId : session.callerId);
      final otherPartyName = isOffenderLocal
          ? (widget.callerSide ? session.listenerName : session.callerNickname)
          : (widget.callerSide ? session.callerNickname : session.listenerName);

      _api.reportNudityIncident(
        sessionId: session.id,
        userId: offenderId,
        userName: offenderName,
        userRole: offenderRole,
        peerId: isOffenderLocal ? (widget.callerSide ? session.listenerId : session.callerId) : (widget.callerSide ? session.callerId : session.listenerId),
        peerName: otherPartyName,
        detectedSource: offenderRole,
        classificationLabel: 'PORN',
        confidenceScore: 0.92,
        actionTaken: 'SCREEN_BLURRED',
        isNudityAllowed: isNudityAllowed,
        snapshotData: snapshot,
      ).catchError((e) {
        debugPrint('[NudityModeration] Background report failed silently: $e');
      });
    }).catchError((_) {});
  }

  void _triggerNudityBlur({String? source}) {
    if (isNudityAllowed) return;
    if (_nudityCooldownActive) return;
    setState(() {
      isNudityBlurred = true;
      nuditySource = source ?? 'peer';
    });
    _sendSignal({
      'type': 'NUDITY_DETECTED',
      'source': source ?? (widget.callerSide ? 'user' : 'listener'),
      'reason': 'Nudity is strictly prohibited',
    });

    // Silently capture unblurred snapshot & report to admin without notifying users
    _reportNudityIncidentSilently(source: source);
  }
  bool _recordingStarted = false;
  late final ApiService _api;
  bool _isDisposed = false;

  @override
  void setState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    super.setState(fn);
  }

  bool get isChat => session.type == 'CHAT';
  bool get isVideo => session.type == 'VIDEO_CALL';
  String get peerName => widget.callerSide ? session.listenerName : session.callerNickname;
  bool get isLive => const {'ACCEPTED', 'CONNECTING', 'CONNECTED', 'ACTIVE'}.contains(session.status);

  Future<void> _startRecordingIfEligible() async {
    if (_recordingStarted || ending || session.ended || isChat) return;

    try {
      final app = mounted ? context.read<AppController>() : null;
      if (app != null) {
        await app.refreshGovernance();
      }

      /*
       * IMPORTANT:
       * On Android, starting native Android MediaRecorder(AudioSource.MIC) or
       * flutter_webrtc MediaRecorder during an active call takes an exclusive
       * hardware lock on the microphone HAL, silencing WebRTC's WebRtcAudioRecord
       * and breaking bi-directional voice transmission.
       * Live WebRTC stream media is safely preserved without hardware HAL collision.
       */
      _recordingStarted = true;
      debugPrint(
        '[RecordingGovernance] Dedicated WebRTC audio/video transmission active for session ${session.id}',
      );
    } catch (e) {
      debugPrint(
        '[RecordingGovernance] Mobile: Error checking recording eligibility: $e',
      );
      _recordingStarted = false;
    }
  }

  Future<void> _stopAndUploadRecording() async {
    if (!_recordingStarted) return;
    _recordingStarted = false;

    try {
      final recordedFile = await CallRecordingService.stopAndCollectRecording();
      if (recordedFile != null && await recordedFile.exists() && await recordedFile.length() > 1000) {
        debugPrint('[Recording] Uploading call recording (${await recordedFile.length()} bytes) for session ${session.id} in background...');
        _api.uploadRecording(session.id, recordedFile).catchError((e) {
          debugPrint('[Recording] Background recording upload error: $e');
          return <String, dynamic>{};
        });
      }
    } catch (e) {
      debugPrint('[Recording] Failed to stop recording: $e');
    }
  }

  @override
void initState() {
  super.initState();

  _api = context.read<AppController>().api;

  WidgetsBinding.instance.addObserver(this);

  everLive = isLive;
  ringRemaining = _initRingRemaining();
  _listenerGiftEarnings = session.giftEarnings;

  if (isVideo) {
    _resetVideoControlsTimer();
  }

  if (widget.callerSide) {
    _api.wallet().then((w) {
      if (mounted) {
        setState(() {
          final total = w.totalBalance > 0 ? w.totalBalance : (w.balance + w.bonusBalance);
          _callerInitialBalance = total;
        });
      }
    }).catchError((_) {});
  }

  /*
   * Initialize RTC renderers ONCE.
   *
   * Previously initialize() was called here without await and then again
   * inside _joinMedia(). That can cause unnecessary Android texture/surface
   * recreation.
   */
  _renderersReady = Future.wait([
    localRenderer.initialize(),
    remoteRenderer.initialize(),
  ]).then((_) {});

  voiceFx.onFrame = (frame) {
    final dc = voiceChannel;

    if (dc == null || !mic) return;

    dc.send(
      RTCDataChannelMessage.fromBinary(frame),
    ).catchError((_) {});
  };

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;

    context.read<AppController>().enterActiveSession();

    registeredActiveSession = true;

    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.bindCallControls(
        toggleMute: _toggleMic,
        endCall: () {
          if (!ending && !session.ended) {
            _end();
          }
        },
        maximizeCall: () {
          if (mounted) {
            setState(() {});
          }
        },
      );
    }
  });

  _startPolling();
  _privacyAlerts.start(_onPrivacyAlert);

  if (!isChat && defaultTargetPlatform != TargetPlatform.iOS) {
    try {
      InCallVoiceSafetyService.instance.startMonitoring(
        sessionId: session.id,
        apiClient: context.read<AppController>().client,
        onLeakageDetected: (warning) {
          if (mounted) {
            setState(() => banner = warning);
          }
        },
      );
    } catch (e) {
      debugPrint('[InCallVoiceSafety] Safe start error: $e');
    }
  }

  // Sub-second connection: join media immediately if already live on mount
  if (isLive && !isChat && pc == null && !joining) {
    unawaited(_joinMedia());
  }
}

  /// Called by PrivacyAlertService whenever native Android detects a
  /// screenshot or screen-recording attempt during an active session.
  void _onPrivacyAlert(String type) {
    // Report silently to backend for admin audit log
    final sId = session.id;
    final apiService = context.read<AppController>().api;
    apiService.securityAlert(sId, type, 'Mobile screenshot/screen-recording attempt detected').catchError((_) {});
    apiService.logInterceptionAudit({
      'sessionId': sId,
      'captureType': type.contains('RECORD') ? 'SCREEN_RECORDING' : 'SCREENSHOT',
      'commandPressed': type,
      'platform': 'MOBILE',
      'actionTaken': 'FLAG_SECURE_BLOCKED',
      'pageUrl': 'mobile/session/' + sId,
    }).catchError((_) => <String, dynamic>{});
    // Show an in-session warning banner to the user
    if (mounted) {
      setState(() => banner = '🚫 Screenshot / recording is prohibited and has been reported.');
    }
  }

  void _startPolling() {
    sessionPoll = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _refreshSession();
    });
    heartbeat = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) _api.sessionHeartbeat(session.id).catchError((_) {});
    });
    clock = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) {
        everLive = true;
        final startStr = session.connectedAt ?? session.startedAt;
        if (startStr != null && startStr.isNotEmpty) {
          final startTime = DateTime.tryParse(startStr)?.toUtc();
          if (startTime != null) {
            final elapsed = DateTime.now().toUtc().difference(startTime).inSeconds;
            if (elapsed >= 0) {
              seconds = elapsed;
            } else {
              seconds++;
            }
          } else {
            seconds++;
          }
        } else {
          seconds++;
        }
        if (!mounted || _isDisposed) return;
        setState(() {});
        if (widget.isHostedInGlobalManager) {
          ActiveCallManager.instance.updateState(
            seconds: seconds,
            muted: !mic,
            live: true,
            updatedSession: session,
          );
        }
      } else if (!session.ended) {
        if (!mounted || _isDisposed) return;
        setState(() {
          elapsedRinging++;
          if (ringRemaining > 0) {
            ringRemaining--;
          }
        });
        if (ringRemaining <= 0 && !ending) {
          _handleRingTimeout();
        }
      }
    });
    messagePoll = Timer.periodic(const Duration(milliseconds: 1100), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) _refreshMessages();
    });
    // Ultra-fast 180ms signal polling during initial negotiation
    signalPoll = Timer.periodic(const Duration(milliseconds: 180), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _pollSignals();
    });
  }

  Future<void> _refreshSession() async {
    if (session.ended || ending || _isDisposed) return;
    try {
      final next = await _api.session(session.id);
      if (!mounted || _isDisposed) return;
      setState(() {
        session = next;
        if (next.giftEarnings > 0 && next.giftEarnings > _listenerGiftEarnings) {
          _listenerGiftEarnings = next.giftEarnings;
        }
        if (_callerInitialBalance == null && next.maxAllowedSeconds > 0) {
          _callerInitialBalance = (next.maxAllowedSeconds / 60.0) * (next.ratePerMinute > 0 ? next.ratePerMinute : 10.0);
        }
        if (isLive) {
          everLive = true;
          final startStr = next.connectedAt ?? next.startedAt;
          if (startStr != null && startStr.isNotEmpty) {
            final startTime = DateTime.tryParse(startStr)?.toUtc();
            if (startTime != null) {
              final elapsed = DateTime.now().toUtc().difference(startTime).inSeconds;
              if (elapsed >= 0) {
                seconds = elapsed;
              }
            }
          } else if (next.durationSeconds > 0 && next.durationSeconds > seconds) {
            seconds = next.durationSeconds;
          }
        }
      });
      if (next.ended) {
        if (!ending) {
          ending = true;
          clock?.cancel();
          sessionPoll?.cancel();
          signalPoll?.cancel();
          heartbeat?.cancel();
          try { localRenderer.srcObject = null; } catch (_) {}
          try { remoteRenderer.srcObject = null; } catch (_) {}
          unawaited(_cleanupMedia());
          if (widget.isHostedInGlobalManager) {
            ActiveCallManager.instance.clearCall();
          } else if (mounted) {
            Navigator.pop(context);
          }
        }
        return;
      } else if (isLive && !isChat && pc == null && !joining) {
        await _joinMedia();
      }
    } catch (_) {}
  }

  Future<MediaStream> _createLocalMediaStream() async {
    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'mandatory': <String, dynamic>{
                'minWidth': 640,
                'minHeight': 480,
                'minFrameRate': 15,
              },
              'optional': <dynamic>[],
            }
          : false,
    };

    try {
      debugPrint('[WebRTC] Requesting local media. video=$isVideo');
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      debugPrint(
        '[WebRTC] getUserMedia success. '
        'stream=${stream.id}, '
        'audioTracks=${stream.getAudioTracks().length}, '
        'videoTracks=${stream.getVideoTracks().length}',
      );
      return stream;
    } catch (e) {
      debugPrint('[WebRTC] Standard camera constraints failed: $e. Retrying front camera fallback...');
      final fallbackConstraints = <String, dynamic>{
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      };
      final stream = await navigator.mediaDevices.getUserMedia(fallbackConstraints);
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      debugPrint(
        '[WebRTC] Fallback getUserMedia success. '
        'stream=${stream.id}, '
        'videoTracks=${stream.getVideoTracks().length}',
      );
      return stream;
    }
  }

    Future<void> _checkAndPromptPermissions(bool isVideo) async {
    final permissions = <Permission>[
      Permission.microphone,
      if (isVideo) Permission.camera,
    ];

    Map<Permission, PermissionStatus> statuses = {};
    try {
      statuses = await permissions.request();
    } catch (e) {
      debugPrint('[Permissions] request error: $e');
    }

    final hasDenied = statuses.values.any((s) => !s.isGranted);
    if (hasDenied) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.perm_device_information_rounded, color: Color(0xFFF97316), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Permission Required', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            content: Text(
              isVideo
                  ? 'Microphone and camera permissions are required to start the video call.\n\nPlease grant permission in Settings to continue.'
                  : 'Microphone permission is required to start the audio call.\n\nPlease grant permission in Settings to continue.',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openAppSettings();
                },
                child: const Text('Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
      throw Exception(
        'Microphone${isVideo ? ' and camera' : ''} permission is required.',
      );
    }
  }

  Future<void> _joinMedia() async {
  if (joining || ending || _isDisposed) {
    return;
  }

  joining = true;

  try {
    final api = context.read<AppController>().api;

    // Start session in background without blocking media initialization
    unawaited(api.startSession(session.id).then((s) {
      session = s;
    }).catchError((e) {
      debugPrint('[WebRTC] startSession warning: $e');
    }));

    /*
     * Permission
     */
    await _checkAndPromptPermissions(isVideo);

    /*
     * Wait until Android RTC render surfaces are initialized.
     */
    await _renderersReady;

    if (ending || _isDisposed || !mounted) {
      return;
    }

    /*
     * ============================================================
     * 1. CREATE CAMERA/MIC STREAM & ICE IN PARALLEL (SUB-SECOND)
     * ============================================================
     */
    final parallelResults = await Future.wait([
      _createLocalMediaStream(),
      api.iceServers(),
    ]);

    if (ending || _isDisposed || !mounted) {
      final capturedStream = parallelResults[0] as MediaStream;
      for (final track in capturedStream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }

      try {
        await capturedStream.dispose();
      } catch (_) {}

      return;
    }

    final capturedStream = parallelResults[0] as MediaStream;
    final ice = parallelResults[1] as List<Map<String, dynamic>>;

    localStream = capturedStream;

    /*
     * Bind the RAW camera stream directly to the local renderer.
     */
    localRenderer.srcObject = capturedStream;

    debugPrint(
      '[WebRTC] Local renderer bound to stream ${capturedStream.id}',
    );

    if (mounted) {
      setState(() {});
    }

    /*
     * ============================================================
     * 2. CREATE PEER CONNECTION
     * ============================================================
     */
    final peer = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'balanced',
      'rtcpMuxPolicy': 'require',
    });

    peer.onIceConnectionState = (state) {
      debugPrint('[WebRTC] Mobile ICE connection state = $state');
      unawaited(_sendSignal({
        'type': 'WEBRTC_DIAG',
        'event': 'ICE_STATE',
        'detail': '$state',
      }));
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('[WebRTC] ICE failed across networks, attempting ICE restart...');
        if (widget.callerSide) {
          _sendOffer(restart: true).catchError((_) {});
        }
      }
    };

    pc = peer;

    /*
     * ============================================================
     * 3. REMOTE TRACK HANDLER & STREAM DISCOVERY
     * ============================================================
     */
    peer.onTrack = (event) async {
      if (_isDisposed || ending) {
        return;
      }

      debugPrint(
        '[WebRTC] Mobile onTrack: '
        'kind=${event.track.kind}, '
        'id=${event.track.id}, '
        'streams=${event.streams.length}',
      );

      // 1. Explicitly enable incoming track
      event.track.enabled = true;

      // 2. Pick up the real remote MediaStream provided by WebRTC (or create fallback if unified-plan streamless)
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
      } else {
        remoteStream ??= await createLocalMediaStream('remote_${session.id}');
        await remoteStream!.addTrack(event.track);
      }

      // 3. Ensure all tracks in remoteStream are active and bind remote renderer
      if (remoteStream != null) {
        for (final track in remoteStream!.getTracks()) {
          track.enabled = true;
        }
        if (remoteRenderer.srcObject != remoteStream) {
          remoteRenderer.srcObject = remoteStream;
        }
      }

      // 4. Force speakerphone so voice audio is routed to loudspeaker
      Helper.setSpeakerphoneOn(speaker).catchError((_) {});

      if (mounted) {
        setState(() {});
      }
    };

    peer.onAddStream = (stream) {
      if (_isDisposed || ending) {
        return;
      }

      debugPrint('[WebRTC] Mobile onAddStream: id=${stream.id}');
      remoteStream = stream;
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      if (remoteRenderer.srcObject != stream) {
        remoteRenderer.srcObject = stream;
      }
      Helper.setSpeakerphoneOn(speaker).catchError((_) {});

      if (mounted) {
        setState(() {});
      }
    };

    /*
     * ============================================================
     * 4. ICE
     * ============================================================
     */
    peer.onIceCandidate = (candidate) {
      final candidateString = candidate.candidate;

      if (candidateString == null ||
          candidateString.trim().isEmpty) {
        return;
      }

      _sendSignal({
        'type': 'candidate',
        'candidate': {
          'candidate': candidateString,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    /*
     * ============================================================
     * 5. DATA CHANNEL
     * ============================================================
     */
    peer.onDataChannel = _attachVoiceChannel;

    /*
     * ============================================================
     * 6. CONNECTION STATE
     * ============================================================
     */
    peer.onConnectionState = (state) {
      if (!mounted || _isDisposed || ending) {
        return;
      }

      debugPrint(
        '[WebRTC] Mobile connection state = $state',
      );

      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _finishReconnect();
        _offerWatchdogTimer?.cancel();
        _offerWatchdogTimer = null;
        // Automatically ensure speakerphone is enabled so incoming audio is loud & clear
        Helper.setSpeakerphoneOn(true).catchError((_) {});
        _startRecordingIfEligible();
        // Relax signaling and session polling once connected
        signalPoll?.cancel();
        signalPoll = Timer.periodic(const Duration(milliseconds: 500), (_) => _pollSignals());
        sessionPoll?.cancel();
        sessionPoll = Timer.periodic(const Duration(milliseconds: 1000), (_) => _refreshSession());

        if (mounted) {
          setState(() {});
        }
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _beginReconnect();
      }
    };

    /*
     * ============================================================
     * 7. ADD LOCAL TRACKS
     * ============================================================
     *
     * Audio first.
     * Video second.
     */
    for (final audioTrack in capturedStream.getAudioTracks()) {
      debugPrint(
        '[WebRTC] Adding LOCAL audio track ${audioTrack.id}',
      );

      await peer.addTrack(
        audioTrack,
        capturedStream,
      );
    }

    for (final videoTrack in capturedStream.getVideoTracks()) {
      debugPrint(
        '[WebRTC] Adding LOCAL video track ${videoTrack.id}',
      );

      await peer.addTrack(
        videoTrack,
        capturedStream,
      );
    }

    /*
     * Print all WebRTC senders.
     */
    final senders = await peer.getSenders();

    for (final sender in senders) {
      debugPrint(
        '[WebRTC] Sender: '
        'kind=${sender.track?.kind}, '
        'track=${sender.track?.id}, '
        'enabled=${sender.track?.enabled}',
      );
    }

    /*
     * ============================================================
     * 8. OPTIONAL DATA CHANNEL FOR CALLER
     * ============================================================
     */
    if (widget.callerSide) {
      final init = RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 0;

      final channel =
          await peer.createDataChannel('voice_fx', init);

      _attachVoiceChannel(channel);
    }

    /*
     * Ultra-fast 180ms signal polling during negotiation.
     */
    signalPoll?.cancel();
    signalPoll = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _pollSignals(),
    );

    /*
     * Tell peer about Android voice-FX support in background.
     */
    unawaited(_sendSignal({
      'type': 'VOICE_FX_CAPABILITY',
      'supported': voiceFx.supported,
    }));

    /*
     * If an offer arrived while camera/mic was initializing, answer it immediately!
     */
    if (pendingOffer != null && !widget.callerSide) {
      final bufferedOffer = pendingOffer!;
      pendingOffer = null;
      debugPrint('[WebRTC] Answering buffered offer immediately after PC ready');
      await _handleRemoteOffer(bufferedOffer);
    }

    /*
     * ============================================================
     * 9. SIGNALING
     * ============================================================
     */
    if (widget.callerSide) {
      await _sendOffer();
    } else {
      await _sendSignal({
        'type': 'peer_ready',
      });
    }

    if (mounted) {
      setState(() {});
    }
  } catch (e, stackTrace) {
    debugPrint(
      '[WebRTC] _joinMedia ERROR: $e',
    );

    debugPrint(
      '[WebRTC] _joinMedia STACK: $stackTrace',
    );

    unawaited(_sendSignal({
      'type': 'WEBRTC_DIAG',
      'event': 'JOIN_MEDIA_ERR',
      'detail': '$e',
    }));

    if (mounted) {
      showError(context, e);
    }
  } finally {
    joining = false;
  }
}

  void _attachVoiceChannel(RTCDataChannel channel) {
    voiceChannel = channel;
    channel.onMessage = (RTCDataChannelMessage data) {
      if (data.isBinary && voiceFx.supported) {
        voiceFx.play(data.binary).catchError((_) {});
      }
    };
    channel.onDataChannelState = (_) {
      if (mounted) setState(() {});
    };
  }

  static String _preferVP8(String sdp) {
    if (!sdp.contains('m=video')) return sdp;
    final lines = sdp.split(RegExp(r'\r\n|\r|\n'));
    int? mVideoIndex;
    String? vp8Payload;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('m=video ')) {
        mVideoIndex = i;
      } else if (line.startsWith('a=rtpmap:') && line.contains('VP8/90000')) {
        final match = RegExp(r'a=rtpmap:(\d+)\s+VP8/90000').firstMatch(line);
        if (match != null) {
          vp8Payload = match.group(1);
        }
      }
    }

    if (mVideoIndex != null && vp8Payload != null) {
      final parts = lines[mVideoIndex].split(' ');
      if (parts.length > 3) {
        final header = parts.sublist(0, 3);
        final payloads = parts.sublist(3);
        payloads.remove(vp8Payload);
        payloads.insert(0, vp8Payload);
        lines[mVideoIndex] = (header + payloads).join(' ');
      }
    }

    return lines.join('\r\n');
  }

  Future<void> _sendOffer({bool restart = false}) async {
    final peer = pc;
    if (peer == null) return;
    if (restart) {
      try { await (peer as dynamic).restartIce(); } catch (_) {}
    }
    final offer = await peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo,
      if (restart) 'iceRestart': true,
    });
    final sdp = _preferVP8(offer.sdp ?? '');
    final finalOffer = RTCSessionDescription(sdp, offer.type);
    await peer.setLocalDescription(finalOffer);
    _lastLocalDesc = finalOffer;
    await _sendSignal({
      'type': 'offer',
      'restart': restart,
      'sdp': {'type': finalOffer.type, 'sdp': finalOffer.sdp},
    });

    if (widget.callerSide && !isChat) {
      _offerWatchdogTimer?.cancel();
      _offerWatchdogTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
        if (!mounted || _isDisposed || ending || session.ended) {
          timer.cancel();
          return;
        }
        final currentPc = pc;
        if (currentPc == null) {
          timer.cancel();
          return;
        }
        final state = await currentPc.getSignalingState();
        final connState = await currentPc.getConnectionState();
        if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            state == RTCSignalingState.RTCSignalingStateStable) {
          timer.cancel();
          return;
        }
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          final localDesc = await _safeGetLocalDescription(currentPc);
          if (localDesc != null) {
            await _sendSignal({
              'type': 'offer',
              'sdp': {'type': localDesc.type, 'sdp': localDesc.sdp},
            });
          }
        }
      });
    }
  }

  void _beginReconnect() async {
    if (reconnecting || ending || session.ended) return;
    try {
      final s = await _api.session(session.id);
      if (s.ended) {
        _finishFromPeer();
        return;
      }
    } catch (_) {}

    reconnecting = true;
    reconnectSeconds = 10;
    if (mounted) setState(() => banner = 'Connection interrupted. Reconnecting… 10s');
    if (widget.callerSide) _sendOffer(restart: true).catchError((_) {});
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || _isDisposed || !reconnecting) {
        t.cancel();
        return;
      }
      reconnectSeconds--;
      if (reconnectSeconds % 2 == 0) {
        try {
          final s = await _api.session(session.id);
          if (s.ended) {
            t.cancel();
            _finishFromPeer();
            return;
          }
        } catch (_) {}
      }
      if (reconnectSeconds <= 0) {
        t.cancel();
        reconnecting = false;
        if (!ending && !session.ended) {
          _end();
        }
        return;
      }
      if (widget.callerSide && reconnectSeconds % 3 == 0) {
        _sendOffer(restart: true).catchError((_) {});
      }
      setState(() => banner = 'Connection interrupted. Reconnecting… ${reconnectSeconds}s');
    });
  }

  void _finishReconnect() {
    reconnectTimer?.cancel();
    if (!reconnecting) return;
    reconnecting = false;
    reconnectSeconds = 30;
    if (mounted) {
      setState(() => banner = 'Connection restored.');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && banner == 'Connection restored.') {
          setState(() => banner = null);
        }
      });
    }
  }

  Future<void> _pollSignals() async {
    if (_isDisposed) return;
    try {
      final list = await _api.signals(
        session.id,
        signalSince,
        _clientId,
        widget.callerSide ? 'caller' : 'listener',
      );
      for (final raw in list) {
        final s = Map<String, dynamic>.from(raw);
        final ts = (s['timestamp'] as num?)?.toInt() ?? signalSince;
        if (ts > signalSince) signalSince = ts;
        try {
          await _processSignal(s);
        } catch (e) {
          debugPrint('[WebRTC] Signal process error (${s['type']}): $e');
          unawaited(_sendSignal({
            'type': 'WEBRTC_DIAG',
            'event': 'SIG_PROC_ERR',
            'detail': '${s['type']}: $e',
          }));
        }
      }
    } catch (_) {}
  }

  Future<void> _processSignal(Map<String, dynamic> s) async {
    final senderClientId = s['senderClientId']?.toString();
    if (senderClientId != null && senderClientId == _clientId) {
      return;
    }
    final senderRole = s['senderRole']?.toString();
    if (senderRole != null && senderRole.toLowerCase() == (widget.callerSide ? 'caller' : 'listener')) {
      return;
    }
    final senderId = s['senderId']?.toString();
    final currentUserId = context.read<AppController>().user?.id;
    if (senderClientId == null && senderRole == null && senderId != null && currentUserId != null && senderId == currentUserId) {
      return;
    }
    final type = '${s['type'] ?? ''}';
    if (const {'call_ended', 'hangup', 'peer_left'}.contains(type)) {
      if (!ending) await _finishFromPeer();
      return;
    }
    if (type == 'gift_sent') {
      final gift = s['gift'] is Map ? Map<String, dynamic>.from(s['gift'] as Map) : null;
      final giftAmt = (gift?['amount'] as num?)?.toDouble() ??
          (gift?['grossAmount'] as num?)?.toDouble() ??
          (gift?['price'] as num?)?.toDouble() ??
          0.0;
      if (mounted) {
        setState(() {
          _listenerGiftEarnings += giftAmt;
          banner = '🎁 Gift received: ${gift?['giftEmoji'] ?? '🎁'} ${gift?['giftName'] ?? 'Gift'}${giftAmt > 0 ? " (+₹${giftAmt.toStringAsFixed(0)})" : ""}';
        });
      }
      return;
    }
    if (type == 'gift_requested') {
      final giftType = '${s['giftType'] ?? 'HEART'}';
      final giftName = '${s['giftName'] ?? 'Gift'}';
      final giftEmoji = '${s['giftEmoji'] ?? '🎁'}';
      final price = (s['giftPrice'] as num?)?.toDouble() ?? 10.0;
      final note = '${s['note'] ?? ''}'.trim();
      final senderName = '${s['senderName'] ?? peerName}';

      if (widget.callerSide && mounted) {
        _showGiftRequestedPrompt(
          giftType: giftType,
          giftName: giftName,
          giftEmoji: giftEmoji,
          price: price,
          note: note.isNotEmpty ? note : null,
          senderName: senderName,
        );
      }
      return;
    }
    if (type == 'TOPIC_BROADCAST') {
      if (mounted) setState(() => banner = '💡 Topic: ${s['topic'] ?? ''}');
      return;
    }
    if (type == 'GAME_ACTION') {
      final payload = s['payload'] is Map ? Map<String, dynamic>.from(s['payload'] as Map) : <String, dynamic>{};
      gameSignal.value = payload;
      if (!gameSheetOpen && mounted) {
        Future.microtask(() => _openGames(fromPeer: true));
      }
      return;
    }
    if (type == 'VIDEO_FILTER_CHANGED') {
      final filter = '${s['filter'] ?? VideoPrivacyFilter.none}';
      if (mounted) {
        setState(() => peerVideoFilter = filter);
      }
      return;
    }
    if (type == 'NUDITY_PERMISSION_TOGGLED') {
      final allowed = s['allowed'] == true;
      if (mounted) {
        setState(() {
          isNudityAllowed = allowed;
          if (allowed) {
            isNudityBlurred = false;
            nuditySource = null;
            banner = '🔞 $peerName enabled Nudity Mode (allowed from both sides)';
          } else {
            banner = '🛡️ $peerName turned off Nudity Mode — protection re-enabled';
          }
        });
      }
      return;
    }
    if (type == 'NUDITY_DETECTED') {
      if (isNudityAllowed) return;
      if (mounted && !_nudityCooldownActive) {
        setState(() {
          isNudityBlurred = true;
          nuditySource = s['source']?.toString() ?? 'peer';
        });
      }
      return;
    }
    if (type == 'NUDITY_ACKNOWLEDGED') {
      return;
    }
    if (type == 'VOICE_FX_CAPABILITY') {
      if (mounted) {
        setState(() => peerVoiceFxCapable = s['supported'] == true);
      }
      return;
    }
    if (type == 'VOICE_FILTER_CHANGED') {
      final filter = '${s['filter'] ?? AndroidVoiceFx.normal}';
      if (mounted) {
        setState(() {
          peerVoiceFilter = filter;
          banner = filter == AndroidVoiceFx.normal ? 'Peer returned to natural voice.' : 'Peer enabled a voice privacy effect.';
        });
      }
      return;
    }
    if (type == 'SAFETY_ALERT') {
      if (mounted) {
        setState(() => banner = '⚠️ ${s['reason'] ?? 'Safety alert'}');
      }
      return;
    }
    if (type == 'peer_ready' && widget.callerSide && !isChat) {
      final peer = pc;
      if (peer != null) {
        final connState = await peer.getConnectionState();
        if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          return;
        }
        final state = await peer.getSignalingState();
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          final offer = await _safeGetLocalDescription(peer);
          if (offer != null) {
            await _sendSignal({
              'type': 'offer',
              'sdp': {'type': offer.type, 'sdp': offer.sdp},
            });
          }
        } else if (state == RTCSignalingState.RTCSignalingStateStable) {
          final localDesc = await _safeGetLocalDescription(peer);
          if (localDesc != null && localDesc.type == 'offer') {
            await _sendSignal({
              'type': 'offer',
              'sdp': {'type': localDesc.type, 'sdp': localDesc.sdp},
            });
          } else {
            await _sendOffer();
          }
        }
      }
      return;
    }
    if (type == 'TYPING_STATUS') {
      final isTyping = s['isTyping'] == true;
      if (mounted) {
        setState(() => isPeerTyping = isTyping);
      }
      _peerTypingTimer?.cancel();
      if (isTyping) {
        _scrollToChatBottom();
        _peerTypingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => isPeerTyping = false);
        });
      }
      return;
    }
    if (type == 'IN_CALL_CHAT' && s['message'] is Map) {
      final msg = Map<String, dynamic>.from(s['message'] as Map);
      if (mounted) {
        setState(() {
          isPeerTyping = false;
          _peerTypingTimer?.cancel();
          final isDup = messages.any((m) =>
            (msg['id'] != null && m['id'] == msg['id']) ||
            (m['text'] == msg['text'] && m['senderRole'] == msg['senderRole'])
          );
          if (!isDup) {
            messages.add(msg);
          }
        });
        _scrollToChatBottom();
      }
      return;
    }

    // Offer handling: if PC is not ready yet, buffer offer so it is NEVER lost!
    if (type == 'offer' && !widget.callerSide) {
      if (pc == null) {
        debugPrint('[WebRTC] Offer arrived before PC ready, buffering in pendingOffer');
        pendingOffer = s;
        return;
      }
      await _handleRemoteOffer(s);
      return;
    }

    // Candidate handling: buffer if PC or remote description not ready yet
    if (type == 'candidate' && s['candidate'] is Map) {
      final c = Map<String, dynamic>.from(s['candidate'] as Map);
      final rawCand = c['candidate']?.toString() ?? '';
      if (rawCand.trim().isEmpty) return;
      final peer = pc;
      if (peer == null) {
        queuedCandidates.add(c);
        return;
      }
      final desc = await peer.getRemoteDescription();
      if (desc == null) {
        queuedCandidates.add(c);
      } else {
        final lineIdx = c['sdpMLineIndex'] is num
            ? (c['sdpMLineIndex'] as num).toInt()
            : int.tryParse('${c['sdpMLineIndex'] ?? ''}');
        final cand = RTCIceCandidate(
          rawCand,
          c['sdpMid']?.toString(),
          lineIdx,
        );
        await peer.addCandidate(cand).catchError((_) {});
      }
      return;
    }

    final peer = pc;
    if (peer == null) return;

    if (type == 'answer' && widget.callerSide) {
      try {
        final d = Map<String, dynamic>.from(s['sdp'] as Map);
        final rawSdp = d['sdp']?.toString() ?? '';
        await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
        await _flushCandidates();
      } catch (e) {
        debugPrint('[WebRTC] Error applying answer: $e');
        unawaited(_sendSignal({
          'type': 'WEBRTC_DIAG',
          'event': 'ANSWER_APPLY_ERR',
          'detail': '$e',
        }));
      }
      return;
    }
  }

  Future<void> _handleRemoteOffer(Map<String, dynamic> s) async {
    final peer = pc;
    if (peer == null) {
      pendingOffer = s;
      return;
    }
    try {
      final localDesc = await _safeGetLocalDescription(peer);
      final signalingState = await peer.getSignalingState();
      final isRestart = s['restart'] == true;
      if (!isRestart && localDesc != null && localDesc.type == 'answer' && signalingState == RTCSignalingState.RTCSignalingStateStable) {
        debugPrint('[WebRTC] Repeat offer received, re-sending existing answer');
        await _sendSignal({
          'type': 'answer',
          'restart': false,
          'sdp': {'type': localDesc.type, 'sdp': localDesc.sdp},
        });
        return;
      }
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      final rawSdp = d['sdp']?.toString() ?? '';
      await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
      final answer = await peer.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      final finalAnswer = RTCSessionDescription(_preferVP8(answer.sdp ?? ''), answer.type);
      await peer.setLocalDescription(finalAnswer);
      _lastLocalDesc = finalAnswer;
      await _sendSignal({
        'type': 'answer',
        'restart': s['restart'] == true,
        'sdp': {'type': finalAnswer.type, 'sdp': finalAnswer.sdp},
      });
      await _flushCandidates();
      debugPrint('[WebRTC] Answer dispatched for remote offer');
    } catch (e) {
      debugPrint('[WebRTC] Error answering offer: $e');
      unawaited(_sendSignal({
        'type': 'WEBRTC_DIAG',
        'event': 'ANSWER_ERR',
        'detail': '$e',
      }));
    }
  }

  Future<void> _flushCandidates() async {
    final peer = pc;
    if (peer == null || queuedCandidates.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(queuedCandidates);
    queuedCandidates.clear();
    for (final c in batch) {
      final rawCand = c['candidate']?.toString() ?? '';
      if (rawCand.trim().isEmpty) continue;
      final lineIdx = c['sdpMLineIndex'] is num
          ? (c['sdpMLineIndex'] as num).toInt()
          : int.tryParse('${c['sdpMLineIndex'] ?? ''}');
      try {
        await peer.addCandidate(RTCIceCandidate(
          rawCand,
          c['sdpMid']?.toString(),
          lineIdx,
        ));
      } catch (_) {}
    }
  }

  Future<void> _refreshMessages() async {
    if (_isDisposed) return;
    try {
      final v = await _api.messages(session.id);
      if (mounted && !_isDisposed) setState(() => messages = v);
    } catch (_) {}
  }

  void _onChatInputChanged(String val) {
    if (val.trim().isNotEmpty) {
      if (!_isMyTypingActive) {
        _isMyTypingActive = true;
        _sendSignal({
          'type': 'TYPING_STATUS',
          'isTyping': true,
        });
      }
      _myTypingTimer?.cancel();
      _myTypingTimer = Timer(const Duration(milliseconds: 2500), () {
        _isMyTypingActive = false;
        if (mounted) {
          _sendSignal({
            'type': 'TYPING_STATUS',
            'isTyping': false,
          });
        }
      });
    } else {
      if (_isMyTypingActive) {
        _isMyTypingActive = false;
        _myTypingTimer?.cancel();
        _sendSignal({
          'type': 'TYPING_STATUS',
          'isTyping': false,
        });
      }
    }
  }

  void _scrollToChatBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    messageController.clear();
    try {
      final app = context.read<AppController>();
      final name = widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener');
      final role = widget.callerSide ? 'USER' : 'LISTENER';
      final newMsg = {
        'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
        'senderId': app.user?.id,
        'senderRole': role,
        'senderName': name,
        'text': text,
        'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (mounted) setState(() => messages.add(newMsg));
      _sendSignal({
        'type': 'IN_CALL_CHAT',
        'message': newMsg,
      });
      await app.api.sendMessage(session.id, text, senderName: name, senderRole: role);
      await _refreshMessages();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  int _initRingRemaining() {
    final expires = DateTime.tryParse(session.expiresAt ?? '')?.toLocal();
    if (expires == null) return 45;
    final left = expires.difference(DateTime.now()).inSeconds;
    if (left <= 0 || left > 45) return 45;
    return left.toInt();
  }

  Future<void> _handleRingTimeout() async {
    if (ending || session.ended) return;
    ending = true;
    try {
      await _sendSignal({
        'type': 'call_ended',
        'reason': 'RING_TIMEOUT',
      });
      await context.read<AppController>().api.cancelSession(session.id);
    } catch (_) {}
    await _cleanupMedia();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Answer'),
        content: Text(
          widget.callerSide
              ? 'Listener did not answer within 45 seconds. No money was deducted.'
              : 'Caller did not answer your callback.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }


  Future<void> _finishFromPeer() async {
    if (ending) return;
    ending = true;

    // Immediately stop timer and pollers
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    InCallVoiceSafetyService.instance.stopMonitoring();
    _privacyAlerts.stop();

    // Immediately detach renderers and stop local hardware tracks
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    unawaited(_cleanupMedia());

    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _end() async {
    _stopRingtone();
    if (ending) return;
    ending = true;

    // 1. Immediately freeze duration timer and cancel all polling
    _videoControlsTimer?.cancel();
    _videoControlsTimer = null;
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    _privacyAlerts.stop();

    // 2. Immediately detach renderers and stop microphone & camera hardware tracks
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    // 3. Dispatch end signals to backend in background
    try {
      _sendSignal({'type': 'call_ended', 'reason': 'USER_ENDED'});
      final api = context.read<AppController>().api;
      api.endSession(session.id).catchError((_) => session);
    } catch (_) {}

    // 4. Cleanup native media in background without blocking UI
    unawaited(_cleanupMedia());

    // 5. Instantly dismiss call UI
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cancel() async {
    _stopRingtone();
    ending = true;
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;

    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    try {
      _sendSignal({
        'type': 'call_ended',
        'reason': 'CALL_CANCELLED',
      });
      final api = context.read<AppController>().api;
      api.cancelSession(session.id).catchError((_) => session);
    } catch (_) {}

    unawaited(_cleanupMedia());

    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cleanupMedia() async {
    _nudityCooldownTimer?.cancel();
    _nudityCooldownTimer = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    messagePoll?.cancel();
    messagePoll = null;
    clock?.cancel();
    clock = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    _privacyAlerts.stop();

    // 1. Detach renderers FIRST before destroying native media objects
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}

    _stopAndUploadRecording();
    try { await voiceFx.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {}); } catch (_) {}
    try { await voiceChannel?.close(); } catch (_) {}
    voiceChannel = null;

    final oldLocal = localStream;
    final oldRemote = remoteStream;
    final oldPc = pc;
    localStream = null;
    remoteStream = null;
    pc = null;
    _lastLocalDesc = null;

    try {
      for (final t in oldLocal?.getTracks() ?? <MediaStreamTrack>[]) {
        try { t.stop(); } catch (_) {}
      }
      for (final t in oldRemote?.getTracks() ?? <MediaStreamTrack>[]) {
        try { t.stop(); } catch (_) {}
      }
      await Future.wait([
        if (oldLocal != null) oldLocal.dispose().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
        if (oldRemote != null) oldRemote.dispose().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
        if (oldPc != null) oldPc.close().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
      ]).timeout(const Duration(milliseconds: 500), onTimeout: () => []);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && !session.ended && !ending) {
      _api.endSession(session.id).catchError((_) => session);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _videoControlsTimer?.cancel();
    _videoControlsTimer = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    messagePoll?.cancel();
    messagePoll = null;
    clock?.cancel();
    clock = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _privacyAlerts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _cleanupMedia();
    if (registeredActiveSession) {
      try { context.read<AppController>().exitActiveSession(); } catch (_) {}
    }
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    localRenderer.dispose();
    remoteRenderer.dispose();
    _peerTypingTimer?.cancel();
    _myTypingTimer?.cancel();
    _chatScrollController.dispose();
    messageController.dispose();
    gameSignal.dispose();
    super.dispose();
  }

  String _time(int value) => '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  void _minimizeCall() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.minimize();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerName = widget.callerSide ? session.listenerName : session.callerNickname;
    final isRinging = !isLive && !session.ended;
    final isCallback = session.reference.startsWith('CB-') || (!widget.callerSide && session.status == 'REQUESTED');
    final peerAvatar = widget.callerSide ? session.listenerAvatarUrl : session.callerAvatarUrl;

    final isChat = session.type == 'CHAT';
    final isVideo = session.type == 'VIDEO_CALL';

    final Color serviceAccent;
    final Color serviceBg;
    final IconData serviceIcon;
    final String serviceShortTag;
    final String servicePillText;
    final String serviceSubtitle;
    final String serviceNoticeText;
    final String serviceCancelText;
    final IconData serviceCancelIcon;
    final String servicePrivacyText;

    if (isVideo) {
      serviceAccent = const Color(0xFF7C3AED); // Royal Violet
      serviceBg = const Color(0xFFF3E8FF);     // Soft Lavender
      serviceIcon = Icons.videocam_rounded;
      serviceShortTag = 'VIDEO CALL';
      servicePillText = isCallback ? 'REQUESTED VIDEO' : 'OUTGOING VIDEO CALL';
      serviceSubtitle = isCallback ? 'Ringing for video callback…' : 'Starting video call…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your video callback.'
          : 'Connecting video call to the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel video call';
      serviceCancelIcon = Icons.videocam_off_outlined;
      servicePrivacyText = isCallback
          ? "Camera connects when they accept."
          : "Your video call stays private and encrypted.";
    } else if (isChat) {
      serviceAccent = const Color(0xFF059669); // Emerald Teal
      serviceBg = const Color(0xFFECFDF5);     // Soft Mint
      serviceIcon = Icons.chat_bubble_rounded;
      serviceShortTag = 'CHAT';
      servicePillText = isCallback ? 'REQUESTED CHAT' : 'OUTGOING CHAT REQUEST';
      serviceSubtitle = isCallback ? 'Waiting for chat callback…' : 'Connecting to chat…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your chat callback.'
          : 'Connecting private chat with the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel chat';
      serviceCancelIcon = Icons.chat_bubble_outline_rounded;
      servicePrivacyText = isCallback
          ? "Chat opens when they accept."
          : "Your chat messages stay private and encrypted.";
    } else {
      serviceAccent = const Color(0xFFF95B3D); // Coral Orange
      serviceBg = const Color(0xFFFFECE5);     // Soft Peach
      serviceIcon = Icons.phone_rounded;
      serviceShortTag = 'VOICE CALL';
      servicePillText = isCallback ? 'REQUESTED AUDIO' : 'OUTGOING';
      serviceSubtitle = isCallback ? 'Ringing for callback…' : 'Calling…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your callback.'
          : 'Connecting you to the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel call';
      serviceCancelIcon = Icons.cancel_outlined;
      servicePrivacyText = isCallback
          ? "You'll be connected when they accept."
          : "Your call stays private and secure.";
    }

    final isMinimized = widget.isHostedInGlobalManager && ActiveCallManager.instance.isMinimized;
    return PopScope(
      canPop: isMinimized || session.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || isMinimized) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (isLive && !session.ended) {
            _minimizeCall();
          } else if (!isLive && !session.ended) {
            final serviceName = isVideo ? 'video call' : (isChat ? 'chat' : 'call');
            final shouldCancel = await confirm(
              context,
              widget.callerSide ? 'Cancel $serviceName request?' : 'Cancel callback?',
              'Do you want to cancel and go back?',
            );
            if (shouldCancel && mounted) {
              await _cancel();
            }
          } else {
            final shouldEnd = await confirm(
              context,
              'End session?',
              'Leaving will end the active session.',
            );
            if (shouldEnd && mounted) {
              await _end();
            }
          }
        });
      },
      child: isRinging
          ? Scaffold(
              backgroundColor: const Color(0xFFFAF5EE),
              appBar: AppBar(
                backgroundColor: const Color(0xFFFAF5EE),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                  onPressed: () async {
                    final serviceName = isVideo ? 'video call' : (isChat ? 'chat' : 'call');
                    if (await confirm(context, widget.callerSide ? 'Cancel $serviceName request?' : 'Cancel callback?', 'Do you want to cancel and go back?')) {
                      await _cancel();
                    }
                  },
                ),
                titleSpacing: 0,
                title: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: serviceBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: serviceAccent.withValues(alpha: 0.3), width: 1),
                      ),
                      child: ClipOval(
                        child: peerAvatar != null && peerAvatar.isNotEmpty
                            ? RemoteAvatar(
                                url: peerAvatar,
                                radius: 17,
                                fallback: peerName,
                              )
                            : Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: serviceAccent,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(serviceIcon, size: 10, color: serviceAccent),
                              const SizedBox(width: 3),
                              Text(
                                serviceShortTag,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: serviceAccent,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              if (session.isTest) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                                  ),
                                  child: const Text(
                                    '🧪 TEST CALL (FREE)',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF0F172A), size: 22),
                    onPressed: _showTools,
                  ),
                ],
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Animated Centerpiece with Service-Themed Waves & Badge
                    Center(
                      child: CallPulseAvatar(
                        name: peerName,
                        avatarUrl: peerAvatar,
                        size: 200,
                        serviceType: session.type,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Status Pill: Service-specific (● OUTGOING VIDEO CALL / ● OUTGOING CHAT / ● OUTGOING)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: serviceBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: serviceAccent.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(serviceIcon, size: 12, color: serviceAccent),
                            const SizedBox(width: 6),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: serviceAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              servicePillText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: serviceAccent,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Peer Name Heading
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        peerName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Subtitle (Service-specific)
                    Text(
                      serviceSubtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Big Timer: 45s remaining countdown
                    Text(
                      '${ringRemaining}s',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: serviceAccent,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'remaining',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info Notice Row (Service-specific)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          serviceIcon,
                          size: 15,
                          color: serviceAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          serviceNoticeText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Outlined Pill Action Button: Cancel callback or Cancel service
                    InkWell(
                      onTap: _cancel,
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        width: 220,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: serviceAccent,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: serviceAccent.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              serviceCancelIcon,
                              size: 18,
                              color: serviceAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              serviceCancelText,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: serviceAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Bottom Privacy Card (Service-specific)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: serviceBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: serviceAccent.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: serviceBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                isVideo
                                    ? Icons.videocam_rounded
                                    : (isChat ? Icons.lock_rounded : Icons.verified_user_rounded),
                                size: 16,
                                color: serviceAccent,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 18,
                              color: serviceAccent.withValues(alpha: 0.3),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            Expanded(
                              child: Text(
                                servicePrivacyText,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : (isChat
              ? _buildLiveChatScreen(peerName, peerAvatar)
              : isVideo
                  ? _buildLiveVideoScreen(peerName, peerAvatar)
                  : _buildLiveAudioScreen(peerName, peerAvatar)),
    );
  }


  /// Floating watermark badge notifying users that contact & bank account sharing is prohibited
  Widget _buildSafetyDeterrenceStrip({bool isVideo = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isVideo ? const Color(0xFF0F172A).withValues(alpha: 0.85) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isVideo ? const Color(0xFF334155) : const Color(0xFFFDBA74),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, color: isVideo ? const Color(0xFFF59E0B) : const Color(0xFFEA580C), size: 13),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Calls monitored • Off-platform contact or bank/UPI sharing strictly prohibited',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isVideo ? const Color(0xFFE2E8F0) : const Color(0xFF9A3412),
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating notification banner for reconnection/security alerts
  Widget _buildTopBanner() {
    if (banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                banner!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => banner = null),
              child: const Icon(Icons.close_rounded, color: Color(0xFF991B1B), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE AUDIO CALL SCREEN (Matches media_1790781859761.png)
  /// -------------------------------------------------------------
  Widget _buildLiveAudioScreen(String peerName, String? peerAvatar) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      body: Stack(
        children: [
          // Background Painter with fluid silk curves and subtle ambient sparkle dots
          Positioned.fill(
            child: CustomPaint(
              painter: SilkWavesPainter(),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar: Minimize button, Center Peer Name, Sparkles/Tools button
                _buildLiveAudioTopBar(peerName),

                // Floating Banner if any
                if (banner != null) _buildTopBanner(),

                // Safety Off-Platform Deterrence Strip
                _buildSafetyDeterrenceStrip(isVideo: false),

                const Spacer(flex: 2),

                // Center Visualizer: Equalizer Waves + Glowing Avatar + Equalizer Waves
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      EqualizerBars(animation: _pulseController, isLeft: true),
                      const SizedBox(width: 8),
                      _buildPickedUpAvatarOrb(peerName, peerAvatar),
                      const SizedBox(width: 8),
                      EqualizerBars(animation: _pulseController, isLeft: false),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Peer Name Heading
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    peerName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Call Duration Timer
                Text(
                  _time(seconds),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),

                // Live Money Pill (Decreasing for Caller, Increasing for Listener)
                _buildLiveMoneyBadge(isDark: false, compact: false),

                if (peerVoiceFilter != AndroidVoiceFx.normal) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECE5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '🎭 Peer voice privacy effect active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF95B3D),
                      ),
                    ),
                  ),
                ],

                const Spacer(flex: 3),

                // Bottom Floating Controls: 3 circular buttons (Mic, Speaker, End Call)
                _buildLiveAudioControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top Bar for Picked-Up Audio Call
  Widget _buildLiveAudioTopBar(String peerName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimize Button (Frosted circular button with downward chevron)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              _minimizeCall();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF4E4D9).withValues(alpha: 0.7),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF1E293B),
                size: 28,
              ),
            ),
          ),

          // Center Peer Name & Live Money Badge
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peerName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                _buildLiveMoneyBadge(isDark: false, compact: true),
              ],
            ),
          ),

          // Tools / Sparkle Button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showTools();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF4E4D9).withValues(alpha: 0.7),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF1E293B),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Real-time live money badge (shows money decreasing for caller, increasing for listener)
  Widget _buildLiveMoneyBadge({bool isDark = false, bool compact = false}) {
    if (widget.callerSide) {
      final balance = _callerRemainingBalance;
      final cost = _currentLiveCost;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF881337).withValues(alpha: 0.45)
              : const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFFF43F5E).withValues(alpha: 0.45)
                : const Color(0xFFFECDD3),
            width: 1.0,
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.arrow_downward_rounded,
              size: compact ? 11 : 13,
              color: isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
            ),
            const SizedBox(width: 3),
            Text(
              '₹${balance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFFFECDD3) : const Color(0xFFBE123C),
                fontFamily: 'monospace',
                letterSpacing: -0.2,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                '(-₹${cost.toStringAsFixed(2)})',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      final earned = _listenerTotalEarnings;
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF064E3B).withValues(alpha: 0.5)
              : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? const Color(0xFF10B981).withValues(alpha: 0.45)
                : const Color(0xFFA7F3D0),
            width: 1.0,
          ),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.trending_up_rounded,
              size: compact ? 12 : 14,
              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
            const SizedBox(width: 3),
            Text(
              '+₹${earned.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                fontFamily: 'monospace',
                letterSpacing: -0.2,
              ),
            ),
            if (_listenerGiftEarnings > 0 && !compact) ...[
              const SizedBox(width: 4),
              const Text(
                '🎁',
                style: TextStyle(fontSize: 10),
              ),
            ],
          ],
        ),
      );
    }
  }

  /// Center glowing avatar orb with concentric aura and silhouette
  Widget _buildPickedUpAvatarOrb(String peerName, String? peerAvatar) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        final scale = 1.0 + 0.02 * pulse;

        return SizedBox(
          width: 250,
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost soft glowing halo
              Container(
                width: 235 * scale,
                height: 235 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF2EB).withValues(alpha: 0.65),
                ),
              ),

              // Middle thin luminous cream ring
              Container(
                width: 195,
                height: 195,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                ),
              ),

              // Inner peach-rose glowing orb
              Container(
                width: 156,
                height: 156,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.15, -0.25),
                    radius: 0.85,
                    colors: [
                      Color(0xFFFFBBA8),
                      Color(0xFFF99D85),
                      Color(0xFFFED8C5),
                    ],
                    stops: [0.0, 0.65, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.28),
                      blurRadius: 34,
                      spreadRadius: 4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: peerAvatar != null && peerAvatar.isNotEmpty
                      ? RemoteAvatar(
                          url: peerAvatar,
                          radius: 78,
                          fallback: peerName,
                        )
                      : _buildDefaultSilhouette(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Translucent white avatar silhouette matching screenshot
  Widget _buildDefaultSilhouette() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 82,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(41)),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Controls Dock for Audio Calls (Mic, Speaker, Gift, Tools, End Call)
  Widget _buildLiveAudioControls() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withOpacity(0.85),
          borderRadius: BorderRadius.circular(38),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Microphone Toggle
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _toggleMic();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mic ? Colors.white.withOpacity(0.12) : const Color(0xFFEF4444).withOpacity(0.85),
                  border: Border.all(
                    color: Colors.white.withOpacity(mic ? 0.2 : 0.4),
                    width: 0.8,
                  ),
                ),
                child: Icon(
                  mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),

            // 2. Speaker Toggle
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _toggleSpeaker();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: speaker ? const Color(0xFF38BDF8).withOpacity(0.2) : Colors.white.withOpacity(0.12),
                  border: Border.all(
                    color: speaker ? const Color(0xFF38BDF8).withOpacity(0.5) : Colors.white.withOpacity(0.2),
                    width: 0.8,
                  ),
                ),
                child: Icon(
                  speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                  color: speaker ? const Color(0xFF38BDF8) : Colors.white,
                  size: 22,
                ),
              ),
            ),

            // 3. Virtual Gift Jewel (Send or Request)
            _buildInCallGiftButton(compact: false),

            // 4. In-Call Tools & Effects
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showTools();
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 0.8,
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),

            // 5. End Call Button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                _end();
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5252), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.5),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE VIDEO CALL SCREEN (Modern State-of-the-Art Luxury)
  /// -------------------------------------------------------------
  Widget _buildLiveVideoScreen(String peerName, String? peerAvatar) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: NudityGuardOverlay(
          isBlurred: isNudityBlurred,
          source: nuditySource == 'local' ? 'Your camera' : (nuditySource != null ? "$nuditySource's camera" : "$peerName's camera"),
          onDismiss: _dismissNudityBlur,
          onAllowNudity: () => _toggleNudityPermission(forcedVal: true),
          child: Stack(
            fit: StackFit.expand,
            children: [
            // 1. Fullscreen Remote Video or Connecting Fallback (with WhatsApp-style tap-to-toggle overlay detector)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _toggleVideoControls();
                },
                child: (remoteRenderer.srcObject != null &&
                        remoteStream != null &&
                        remoteStream!.getVideoTracks().isNotEmpty)
                    ? FilteredVideoView(
                        filter: peerVideoFilter,
                        child: RTCVideoView(
                          remoteRenderer,
                          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      )
                    : _buildVideoConnectingFallback(peerName, peerAvatar),
              ),
            ),

            // 2. Subtle Cinematic Vignette Overlays (fade out when controls hide)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Floating PiP Local Video (smoothly glides higher when controls hide)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              right: 16,
              top: _areVideoControlsVisible ? (topPadding + 62) : (topPadding + 16),
              width: 108,
              height: 154,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _resetVideoControlsTimer();
                  _switchCamera();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                       children: [
                         // Local camera view — ValueKey forces widget recreation when filter changes
                         // This ensures the ColorFilter is fully removed from the render tree on reset
                         if (camera)
                           FilteredVideoView(
                             key: ValueKey(activeVideoFilter),
                             filter: activeVideoFilter,
                             showBadge: false,
                             child: RTCVideoView(
                               localRenderer,
                               key: ValueKey('local_$activeVideoFilter'),
                               mirror: true,
                               objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                             ),
                           )
                         else
                           Container(
                             color: const Color(0xFF1E2433),
                             child: Center(
                               child: Column(
                                 mainAxisSize: MainAxisSize.min,
                                 children: [
                                   Container(
                                     padding: const EdgeInsets.all(8),
                                     decoration: BoxDecoration(
                                       color: Colors.white.withValues(alpha: 0.08),
                                       shape: BoxShape.circle,
                                     ),
                                     child: const Icon(
                                       Icons.videocam_off_rounded,
                                       size: 22,
                                       color: Color(0xFFEF4444),
                                     ),
                                   ),
                                   const SizedBox(height: 6),
                                   const Text(
                                     'Camera Off',
                                     style: TextStyle(
                                       color: Colors.white70,
                                       fontSize: 11,
                                       fontWeight: FontWeight.w600,
                                     ),
                                   ),
                                 ],
                               ),
                             ),
                           ),

                        // Tap-to-flip camera icon badge at bottom-right corner of PiP
                        if (camera)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _switchCamera();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.55),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.flip_camera_ios_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4. Floating Top Bar (Strictly positioned at the top, animated fade)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_areVideoControlsVisible,
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Minimize Call Button
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _minimizeCall();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Peer Name & Live Duration Timer Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 95),
                              child: Text(
                                peerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _time(seconds),
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Live Money Badge (Decreasing for Caller / Increasing for Listener)
                      _buildLiveMoneyBadge(isDark: true, compact: false),

                      const Spacer(),

                      // Tools / Sparkle Button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _resetVideoControlsTimer();
                          _showTools();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                ),
              ),
            ),

            // Top Banner if active
            if (banner != null)
              Positioned(
                top: topPadding + 62,
                left: 16,
                right: 136,
                child: IgnorePointer(
                  ignoring: !_areVideoControlsVisible,
                  child: AnimatedOpacity(
                    opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: _buildTopBanner(),
                  ),
                ),
              ),

            // Safety Off-Platform Deterrence Strip
            Positioned(
              top: topPadding + (banner != null ? 116 : 62),
              left: 16,
              right: 136,
              child: IgnorePointer(
                ignoring: !_areVideoControlsVisible,
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: _buildSafetyDeterrenceStrip(isVideo: true),
                ),
              ),
            ),

            // 4. Secondary Floating Contextual Micro-Pills (Nudity Shield, Video Filters, Speaker)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPadding + 82,
              child: IgnorePointer(
                ignoring: !_areVideoControlsVisible,
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Nudity Mode Micro-Pill
                      _buildFloatingMicroPill(
                        icon: isNudityAllowed ? Icons.shield_rounded : Icons.shield_outlined,
                        label: isNudityAllowed ? '18+ Allowed' : 'Safety Shield',
                        isActive: isNudityAllowed,
                        activeColor: const Color(0xFFEC4899),
                        onTap: () {
                          _resetVideoControlsTimer();
                          _toggleNudityPermission();
                        },
                      ),
                      const SizedBox(width: 8),
                      // Video Filter Micro-Pill
                      _buildFloatingMicroPill(
                        icon: Icons.face_retouching_natural_rounded,
                        label: activeVideoFilter == VideoPrivacyFilter.none ? 'Filters' : 'Filter ON',
                        isActive: activeVideoFilter != VideoPrivacyFilter.none,
                        activeColor: const Color(0xFFA855F7),
                        onTap: () {
                          _resetVideoControlsTimer();
                          _videoFilters();
                        },
                      ),
                      const SizedBox(width: 8),
                      // Speaker Micro-Pill
                      _buildFloatingMicroPill(
                        icon: speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: speaker ? 'Speaker' : 'Earpiece',
                        isActive: speaker,
                        activeColor: const Color(0xFF38BDF8),
                        onTap: () {
                          _resetVideoControlsTimer();
                          _toggleSpeaker();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 5. Floating Bottom Controls Dock (5 Balanced Luxury Buttons)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPadding + 14,
              child: IgnorePointer(
                ignoring: !_areVideoControlsVisible,
                child: AnimatedOpacity(
                  opacity: _areVideoControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Mic
                        _buildVideoGlassButton(
                          icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                          isActive: mic,
                          tooltip: mic ? 'Mute microphone' : 'Unmute microphone',
                          onTap: () {
                            _resetVideoControlsTimer();
                            _toggleMic();
                          },
                        ),
                        // Video Camera
                        _buildVideoGlassButton(
                          icon: camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          isActive: camera,
                          tooltip: camera ? 'Turn off camera' : 'Turn on camera',
                          onTap: () {
                            _resetVideoControlsTimer();
                            _toggleCamera();
                          },
                        ),
                        // Virtual Gift Button (Centerpiece Jewel for both Caller & Listener)
                        _buildInCallGiftButton(compact: false),
                        // Camera Switch (Front/Back)
                        _buildVideoGlassButton(
                          icon: Icons.flip_camera_ios_rounded,
                          isActive: true,
                          tooltip: 'Switch camera',
                          onTap: () {
                            _resetVideoControlsTimer();
                            _switchCamera();
                          },
                        ),
                        // End Call Button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.heavyImpact();
                            _end();
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF5252), Color(0xFFDC2626)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.call_end_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// Modern full-screen connecting fallback for video call
  Widget _buildVideoConnectingFallback(String peerName, String? peerAvatar) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.2,
          colors: [
            Color(0xFF1E1B4B), // Deep indigo
            Color(0xFF0F172A), // Slate navy
            Color(0xFF060913), // Deep obsidian
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVideoConnectingAvatarOrb(peerName, peerAvatar),
                const SizedBox(height: 22),
                Text(
                  peerName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFA78BFA).withValues(alpha: 0.45),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Connecting video feed…',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'End-to-end encrypted private video',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Glowing neon-accented avatar orb for video screen connecting state
  Widget _buildVideoConnectingAvatarOrb(String peerName, String? peerAvatar) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        final scale = 1.0 + 0.05 * pulse;

        return SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost soft glowing violet halo
              Container(
                width: 165 * scale,
                height: 165 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.22 * (1.0 - pulse * 0.3)),
                ),
              ),

              // Middle neon accent ring
              Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFA78BFA).withValues(alpha: 0.45 + 0.35 * pulse),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // Inner avatar circle
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: peerAvatar != null && peerAvatar.isNotEmpty
                      ? RemoteAvatar(
                          url: peerAvatar,
                          radius: 62,
                          fallback: peerName,
                        )
                      : Container(
                          color: const Color(0xFF1E293B),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 58,
                            color: Color(0xFFA78BFA),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoGlassButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    bool isFilter = false,
    bool isNudity = false,
    String? tooltip,
  }) {
    final Color bgColor;
    final Color iconColor;
    if (isNudity) {
      bgColor = isActive
          ? const Color(0xFFEC4899).withValues(alpha: 0.88)
          : Colors.white.withValues(alpha: 0.12);
      iconColor = Colors.white;
    } else if (isFilter) {
      bgColor = isActive
          ? const Color(0xFF7C3AED).withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.12);
      iconColor = isActive ? Colors.white : Colors.white.withValues(alpha: 0.9);
    } else {
      bgColor = isActive
          ? Colors.white.withValues(alpha: 0.14)
          : const Color(0xFFEF4444).withValues(alpha: 0.88);
      iconColor = Colors.white;
    }

    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(
              color: Colors.white.withValues(alpha: isActive ? 0.2 : 0.4),
              width: 0.8,
            ),
            boxShadow: (isNudity && isActive)
                ? [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : (isActive
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 21,
          ),
        ),
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE CHAT SCREEN (Silk Cream Luxury HearMe Theme)
  /// -------------------------------------------------------------
  Widget _buildLiveChatScreen(String peerName, String? peerAvatar) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF5EE),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: Color(0xFF0F172A)),
          tooltip: 'Minimize chat',
          onPressed: _minimizeCall,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFFFECE5),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: peerAvatar != null && peerAvatar.isNotEmpty
                    ? RemoteAvatar(
                        url: peerAvatar,
                        radius: 18,
                        fallback: peerName,
                      )
                    : const Center(
                        child: Icon(Icons.person_rounded, size: 22, color: Color(0xFFF95B3D)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        isPeerTyping ? 'typing…' : 'Chatting • ${_time(seconds)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isPeerTyping ? const Color(0xFF059669) : const Color(0xFFF95B3D),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildLiveMoneyBadge(isDark: false, compact: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _gift();
            },
            tooltip: widget.callerSide ? 'Send a Gift' : 'Request a Gift',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFECE5),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF95B3D).withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.card_giftcard_rounded,
                color: Color(0xFFF95B3D),
                size: 18,
              ),
            ),
          ),
          IconButton(
            onPressed: _showTools,
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF0F172A)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                _end();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'End',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (banner != null) _buildTopBanner(),

          // Security & anonymity reassurance pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: Color(0xFFF95B3D)),
                SizedBox(width: 6),
                Text(
                  'End-to-end encrypted • Anonymous Chat',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF95B3D),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(child: _chatBody()),

          // Quick Action Pills Row (Icebreakers, Gifts, Games)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildQuickActionChip(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'Topic',
                  onTap: _topic,
                ),
                _buildQuickActionChip(
                  icon: Icons.card_giftcard_rounded,
                  label: widget.callerSide ? 'Send Gift 🎁' : 'Request Gift 🎁',
                  onTap: _gift,
                  isSpecial: true,
                ),
                _buildQuickActionChip(
                  icon: Icons.sports_esports_rounded,
                  label: 'Play Game',
                  onTap: () => _openGames(),
                ),
                _buildQuickActionChip(
                  icon: Icons.report_outlined,
                  label: 'Report',
                  onTap: _report,
                ),
              ],
            ),
          ),

          // Chat Input Bar
          _chatInput(),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSpecial = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSpecial ? const Color(0xFFFFF1EE) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSpecial ? const Color(0xFFF95B3D) : const Color(0xFFFFECE5),
              width: isSpecial ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFFF95B3D)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSpecial ? const Color(0xFFF95B3D) : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatBody() => ListView.builder(
        controller: _chatScrollController,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: messages.length + (isPeerTyping ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == messages.length && isPeerTyping) {
            final peerName = widget.callerSide ? session.listenerName : session.callerNickname;
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$peerName is typing…',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF059669),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final m = Map<String, dynamic>.from(messages[i]);
          final mine = (m['senderRole'] == 'USER') == widget.callerSide;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: mine
                    ? const LinearGradient(
                        colors: [Color(0xFFF95B3D), Color(0xFFFF7A59)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: mine ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                border: mine
                    ? null
                    : Border.all(
                        color: const Color(0xFFFFECE5),
                        width: 1,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${m['senderName'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF95B3D),
                        ),
                      ),
                    ),
                  Text(
                    '${m['text'] ?? ''}',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: mine ? Colors.white : const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _chatInput() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFFFECE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    onChanged: _onChatInputChanged,
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      hintStyle: TextStyle(fontSize: 14.5, color: Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _gift();
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECE5),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF95B3D).withValues(alpha: 0.25)),
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: Color(0xFFF95B3D),
                      size: 19,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFF95B3D), Color(0xFFFF7A59)],
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );


  Future<void> _switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
      if (mounted) setState(() {});
    }
  }

  void _toggleMic() {
    final next = !mic;
    mic = next;
    if (nativeVoiceFxActive) {
      for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = false;
      }
      if (next) {
        voiceFx.start(activeVoiceFilter).catchError((_) {});
      } else {
        voiceFx.stopCapture().catchError((_) {});
      }
    } else {
      for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = next;
      }
    }
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.updateState(
        seconds: seconds,
        muted: !next,
        live: isLive,
        updatedSession: session,
      );
    }
    setState(() {});
  }

  void _toggleCamera() {
    camera = !camera;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camera;
    }
    setState(() {});
  }

  void _toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker).catchError((_) {});
    setState(() {});
  }

  Widget _buildFloatingMicroPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.24)
              : const Color(0xFF10172A).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
            if (isActive)
              BoxShadow(
                color: activeColor.withValues(alpha: 0.28),
                blurRadius: 8,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? activeColor : const Color(0xFFE2E8F0),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : const Color(0xFFE2E8F0),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInCallGiftButton({bool compact = false}) {
    final isCaller = widget.callerSide;
    final gradientColors = isCaller
        ? const [Color(0xFFF59E0B), Color(0xFFEC4899)]
        : const [Color(0xFF8B5CF6), Color(0xFFEC4899)];
    final shadowColor = isCaller ? const Color(0xFFF59E0B) : const Color(0xFFEC4899);

    return Tooltip(
      message: isCaller ? 'Send a Virtual Gift' : 'Request a Virtual Gift',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          _gift();
        },
        child: Container(
          width: compact ? 48 : 52,
          height: compact ? 48 : 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.48),
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎁',
                style: TextStyle(fontSize: 19, height: 1.1),
              ),
              Text(
                isCaller ? 'Gift' : 'Ask',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLuxuryToolTile({
    required IconData icon,
    required List<Color> gradientColors,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.first.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ] else ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.35),
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGiftRequestedPrompt({
    required String giftType,
    required String giftName,
    required String giftEmoji,
    required double price,
    String? note,
    required String senderName,
  }) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(giftEmoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Gift Request from $senderName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '$senderName requested a $giftName (₹${price.toStringAsFixed(0)})',
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"$note"',
                    style: const TextStyle(
                      color: Color(0xFFF472B6),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF94A3B8))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final sent = await context.read<AppController>().api.sendGift(
                            session.id,
                            giftType,
                            note: note,
                          );
                          await _sendSignal({'type': 'gift_sent', 'gift': sent});
                          if (mounted) {
                            final giftAmt = (sent['amount'] as num?)?.toDouble() ??
                                (sent['grossAmount'] as num?)?.toDouble() ??
                                (sent['price'] as num?)?.toDouble() ??
                                price;
                            setState(() {
                              _callerGiftsSpent += giftAmt;
                              banner = '🎁 Sent $giftEmoji $giftName (₹${giftAmt.toStringAsFixed(0)}) to $senderName';
                            });
                          }
                        } catch (e) {
                          if (mounted) showError(context, e);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Send ₹${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTools() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF0A0F1D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 35,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'In-Call Tools & Features',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            'Enhance conversation, privacy & engagement',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 16),

              // Scrollable list of luxury cards
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      // Virtual Gift Hero Card
                      _buildLuxuryToolTile(
                        icon: widget.callerSide ? Icons.card_giftcard_rounded : Icons.volunteer_activism_rounded,
                        gradientColors: widget.callerSide
                            ? const [Color(0xFFF59E0B), Color(0xFFEC4899)]
                            : const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        title: widget.callerSide ? 'Send a Virtual Gift' : 'Request a Virtual Gift',
                        subtitle: widget.callerSide
                            ? 'Surprise $peerName with flowers, chocolates or a crown'
                            : 'Ask $peerName for a token of appreciation',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.callerSide
                                  ? const [Color(0xFFF59E0B), Color(0xFFEC4899)]
                                  : const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.callerSide ? 'Send 🎁' : 'Request 🎁',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _gift();
                        },
                      ),

                      // In-Call Chat
                      if (!isChat)
                        _buildLuxuryToolTile(
                          icon: Icons.chat_bubble_outline_rounded,
                          gradientColors: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                          title: 'In-Call Chat',
                          subtitle: 'Exchange text messages quietly while talking',
                          onTap: () {
                            Navigator.pop(ctx);
                            _inCallChat();
                          },
                        ),

                      // Voice Privacy Effects
                      if (!isChat)
                        _buildLuxuryToolTile(
                          icon: Icons.graphic_eq_rounded,
                          gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                          title: 'Voice Privacy Effects',
                          subtitle: _voiceLabel(activeVoiceFilter),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              activeVoiceFilter == AndroidVoiceFx.normal ? 'Natural' : 'Active',
                              style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _voiceFilters();
                          },
                        ),

                      // Video Masks & Privacy Filters
                      if (isVideo)
                        _buildLuxuryToolTile(
                          icon: Icons.face_retouching_natural_rounded,
                          gradientColors: const [Color(0xFFEC4899), Color(0xFFA855F7)],
                          title: 'Video Masks & Privacy Filters',
                          subtitle: _videoLabel(activeVideoFilter),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEC4899).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              activeVideoFilter == VideoPrivacyFilter.none ? 'Original' : 'Filter ON',
                              style: const TextStyle(color: Color(0xFFF9A8D4), fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _videoFilters();
                          },
                        ),

                      // Nudity Mode Mutual Consent
                      if (isVideo)
                        _buildLuxuryToolTile(
                          icon: isNudityAllowed ? Icons.shield_rounded : Icons.shield_outlined,
                          gradientColors: isNudityAllowed
                              ? const [Color(0xFFEC4899), Color(0xFFD946EF)]
                              : const [Color(0xFF10B981), Color(0xFF059669)],
                          title: isNudityAllowed ? 'Nudity Mode is ON (Allowed)' : 'Mutual Nudity Consent',
                          subtitle: isNudityAllowed
                              ? 'Adult content permitted from both sides. Tap to disable.'
                              : 'Both sides must consent to permit adult content without blur',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (isNudityAllowed ? const Color(0xFFEC4899) : const Color(0xFF10B981)).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isNudityAllowed ? const Color(0xFFEC4899) : const Color(0xFF10B981)).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              isNudityAllowed ? '18+ ON' : 'PROTECTED',
                              style: TextStyle(
                                color: isNudityAllowed ? const Color(0xFFF472B6) : const Color(0xFF6EE7B7),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleNudityPermission();
                          },
                        ),

                      // Trigger Safety Blur
                      if (isVideo && !isNudityAllowed)
                        _buildLuxuryToolTile(
                          icon: Icons.visibility_off_rounded,
                          gradientColors: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                          title: 'Trigger Instant Safety Blur',
                          subtitle: 'Instantly blur video stream on both ends for privacy',
                          onTap: () {
                            Navigator.pop(ctx);
                            _triggerNudityBlur(source: 'peer');
                          },
                        ),

                      // Icebreaker Topics
                      _buildLuxuryToolTile(
                        icon: Icons.lightbulb_rounded,
                        gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                        title: 'Icebreaker Topics',
                        subtitle: 'AI conversation sparkers & deep questions',
                        onTap: () {
                          Navigator.pop(ctx);
                          _topic();
                        },
                      ),

                      // Mini Games
                      _buildLuxuryToolTile(
                        icon: Icons.sports_esports_rounded,
                        gradientColors: const [Color(0xFF10B981), Color(0xFF0D9488)],
                        title: 'Open Mini Games',
                        subtitle: 'Tic-Tac-Toe • Would You Rather • 20 Questions',
                        onTap: () {
                          Navigator.pop(ctx);
                          _openGames();
                        },
                      ),

                      // Report
                      _buildLuxuryToolTile(
                        icon: Icons.flag_rounded,
                        gradientColors: const [Color(0xFF64748B), Color(0xFF475569)],
                        title: 'Report Participant',
                        subtitle: 'Discreetly flag abusive or non-consensual behavior',
                        onTap: () {
                          Navigator.pop(ctx);
                          _report();
                        },
                      ),

                      // End Consultation
                      _buildLuxuryToolTile(
                        icon: Icons.call_end_rounded,
                        gradientColors: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                        title: 'End Consultation',
                        subtitle: 'Hang up and conclude this session',
                        onTap: () {
                          Navigator.pop(ctx);
                          _end();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _voiceLabel(String id) => AndroidVoiceFx.options.firstWhere((x) => x.id == id, orElse: () => AndroidVoiceFx.options.first).label;
  String _videoLabel(String id) => VideoPrivacyFilter.options.firstWhere((x) => x['id'] == id, orElse: () => VideoPrivacyFilter.options.first)['label']!;

  Future<void> _voiceFilters() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Voice privacy effects'),
        children: AndroidVoiceFx.options.map((o) => RadioListTile<String>(
          value: o.id,
          groupValue: activeVoiceFilter,
          title: Text('${o.emoji} ${o.label}'),
          subtitle: Text(o.description),
          onChanged: (v) => Navigator.pop(ctx, v),
        )).toList(),
      ),
    );
    if (selected == null || selected == activeVoiceFilter) return;
    if (selected != AndroidVoiceFx.normal && !voiceFx.supported) {
      if (mounted) showError(context, Exception('Voice effects are currently available on Android.'));
      return;
    }
    if (selected != AndroidVoiceFx.normal && !peerVoiceFxCapable) {
      if (mounted) {
        showError(context, Exception('This voice effect requires the other participant to use the TalkStrangers Android app. Natural WebRTC audio will continue normally.'));
      }
      return;
    }

    activeVoiceFilter = selected;
    nativeVoiceFxActive = selected != AndroidVoiceFx.normal;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = mic && !nativeVoiceFxActive;
    }
    if (nativeVoiceFxActive && mic) {
      await voiceFx.start(selected);
    } else {
      await voiceFx.stopCapture();
    }
    await _sendSignal({'type': 'VOICE_FILTER_CHANGED', 'filter': selected});
    if (mounted) setState(() {});
  }

  Future<void> _videoFilters() async {
  final selected = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Video privacy filters'),
      children: [
        if (activeVideoFilter != VideoPrivacyFilter.none)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              8,
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(
                Icons.videocam_rounded,
                size: 18,
              ),
              label: const Text(
                '📷 Show Real Camera (Remove Filter)',
              ),
              onPressed: () {
                Navigator.pop(
                  ctx,
                  VideoPrivacyFilter.none,
                );
              },
            ),
          ),

        ...VideoPrivacyFilter.options.map(
          (option) => RadioListTile<String>(
            value: option['id']!,
            groupValue: activeVideoFilter,
            title: Text(
              '${option['emoji']} ${option['label']}',
            ),
            subtitle: Text(
              option['description']!,
            ),
            onChanged: (value) {
              Navigator.pop(ctx, value);
            },
          ),
        ),
      ],
    ),
  );

  if (selected == null ||
      selected == activeVideoFilter) {
    return;
  }

  if (mounted) {
    setState(() {
      activeVideoFilter = selected;
    });
  } else {
    activeVideoFilter = selected;
  }

  /*
   * The filter is a Flutter UI overlay.
   *
   * There is NO need to destroy/re-bind the native RTC texture.
   */
  await _sendSignal({
    'type': 'VIDEO_FILTER_CHANGED',
    'filter': selected,
  });
}

  Future<void> _inCallChat() async {
    await _refreshMessages();
    if (!mounted) return;
    final controller = TextEditingController();
    Timer? localPoll;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        localPoll ??= Timer.periodic(const Duration(milliseconds: 900), (_) async {
          try {
            messages = await context.read<AppController>().api.messages(session.id);
            if (ctx.mounted) setLocal(() {});
          } catch (_) {}
        });
        Future<void> send() async {
          final text = controller.text.trim();
          if (text.isEmpty) return;
          controller.clear();
          final app = context.read<AppController>();
          final name = widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener');
          final role = widget.callerSide ? 'USER' : 'LISTENER';
          final newMsg = {
            'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
            'senderId': app.user?.id,
            'senderRole': role,
            'senderName': name,
            'text': text,
            'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            'timestamp': DateTime.now().toIso8601String(),
          };
          messages.add(newMsg);
          if (ctx.mounted) setLocal(() {});
          _sendSignal({
            'type': 'IN_CALL_CHAT',
            'message': newMsg,
          });
          await app.api.sendMessage(session.id, text, senderName: name, senderRole: role);
          messages = await app.api.messages(session.id);
          if (ctx.mounted) setLocal(() {});
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .68,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Text('In-call chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _gift();
                      },
                      icon: const Icon(Icons.card_giftcard_rounded, size: 16, color: Color(0xFFF95B3D)),
                      label: Text(
                        widget.callerSide ? 'Send Gift 🎁' : 'Request Gift 🎁',
                        style: const TextStyle(
                          color: Color(0xFFF95B3D),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: messages.length, itemBuilder: (_, i) {
                final m = Map<String, dynamic>.from(messages[i]);
                return ListTile(dense: true, title: Text('${m['senderName'] ?? ''}'), subtitle: Text('${m['text'] ?? ''}'));
              })),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onSubmitted: (_) => send(),
                          decoration: const InputDecoration(hintText: 'Message…'),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _gift();
                        },
                        tooltip: widget.callerSide ? 'Send Gift' : 'Request Gift',
                        icon: const Icon(Icons.card_giftcard_rounded, color: Color(0xFFF95B3D)),
                      ),
                      IconButton.filled(
                        onPressed: send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
    localPoll?.cancel();
    controller.dispose();
  }

  Future<void> _gift() async {
    try {
      final isListener = !widget.callerSide;
      final result = await InCallGiftingSheet.show(
        context,
        sessionId: session.id,
        listenerName: peerName,
        isListenerRequest: isListener,
        onRechargeRequested: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WalletScreen()),
          );
        },
      );
      if (result != null && mounted) {
        if (isListener) {
          final emoji = result['giftEmoji'] ?? '🎁';
          final name = result['giftName'] ?? 'Gift';
          final price = (result['giftPrice'] as num?)?.toDouble() ?? 0.0;
          setState(() {
            banner = '🎁 Requested $emoji $name${price > 0 ? " (₹${price.toStringAsFixed(0)})" : ""} from $peerName';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Requested $name from $peerName!'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          final giftAmt = (result['amount'] as num?)?.toDouble() ??
              (result['grossAmount'] as num?)?.toDouble() ??
              (result['price'] as num?)?.toDouble() ??
              0.0;
          setState(() {
            _callerGiftsSpent += giftAmt;
            banner = '🎁 Gift sent: ${result['giftEmoji'] ?? '🎁'} ${result['giftName'] ?? 'Gift'}${giftAmt > 0 ? " (₹${giftAmt.toStringAsFixed(0)})" : ""}';
          });
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _topic() async {
    const topics = [
      'What made you smile recently?',
      'What is something you wish people understood about you?',
      'If you could travel anywhere tomorrow, where would you go?',
      'What song matches your mood today?',
      'What is one small thing you are grateful for?',
    ];
    final topic = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a topic'),
        children: topics.map((t) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Padding(padding: const EdgeInsets.all(8), child: Text(t)))).toList(),
      ),
    );
    if (topic != null) {
      await _sendSignal({'type': 'TOPIC_BROADCAST', 'topic': topic});
      if (mounted) setState(() => banner = '💡 Topic: $topic');
    }
  }

  Future<void> _openGames({bool fromPeer = false}) async {
    if (!mounted || gameSheetOpen) return;
    gameSheetOpen = true;
    if (!fromPeer) {
      await _sendSignal({
        'type': 'GAME_ACTION',
        'payload': {'game': 'TTT', 'action': 'OPEN', 'data': <String, dynamic>{}}
      });
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InCallMiniGames(
        isCaller: widget.callerSide,
        incomingSignal: gameSignal,
        send: (payload) => _sendSignal({'type': 'GAME_ACTION', 'payload': payload}),
      ),
    );
    gameSheetOpen = false;
  }

  Future<void> _report() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report'),
        content: TextField(controller: c, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Submit')),
        ],
      ),
    );
    c.dispose();
    if (text != null && text.trim().isNotEmpty) {
      final target = widget.callerSide ? (session.listenerUserId ?? session.listenerId) : (session.callerId ?? '');
      try {
        await context.read<AppController>().api.reportUser(target, sessionId: session.id, reason: 'SESSION_REPORT', description: text.trim());
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

}

/// Animated multi-bar soundwave equalizer for live call
class EqualizerBars extends StatelessWidget {
  final Animation<double> animation;
  final bool isLeft;

  const EqualizerBars({
    super.key,
    required this.animation,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    // 6 bars with harmonious resting and active heights
    final baseHeights = isLeft
        ? const [14.0, 22.0, 38.0, 48.0, 30.0, 16.0]
        : const [16.0, 30.0, 48.0, 38.0, 22.0, 14.0];

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(baseHeights.length, (i) {
            final phase = (i * 0.22);
            final wave = 0.5 + 0.5 * ((t + phase) % 1.0);
            final dynamicHeight = (baseHeights[i] * (0.65 + 0.45 * wave)).clamp(8.0, 50.0);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.2),
              width: 3.5,
              height: dynamicHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.5),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFDBA74).withValues(alpha: 0.85),
                    const Color(0xFFF97316).withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Custom painter for soft peach silk waves and subtle ambient sparkle dots
class SilkWavesPainter extends CustomPainter {
  SilkWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base background gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF9F5), Color(0xFFFDECE2), Color(0xFFFAF0E6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Wave 1: Flowing from top left across to right
    final wave1Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFCEADE).withValues(alpha: 0.65),
          const Color(0xFFFADCCB).withValues(alpha: 0.35),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, h * 0.14);
    path1.cubicTo(w * 0.3, h * 0.22, w * 0.7, h * 0.08, w, h * 0.26);
    path1.lineTo(w, h * 0.40);
    path1.cubicTo(w * 0.6, h * 0.24, w * 0.25, h * 0.36, 0, h * 0.24);
    path1.close();
    canvas.drawPath(path1, wave1Paint);

    // Wave 2: Sweeping across lower-middle
    final wave2Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFDE8DC).withValues(alpha: 0.55),
          const Color(0xFFF9D6C4).withValues(alpha: 0.30),
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, h * 0.54);
    path2.cubicTo(w * 0.35, h * 0.66, w * 0.65, h * 0.50, w, h * 0.70);
    path2.lineTo(w, h * 0.84);
    path2.cubicTo(w * 0.6, h * 0.68, w * 0.3, h * 0.80, 0, h * 0.68);
    path2.close();
    canvas.drawPath(path2, wave2Paint);

    // Wave 3: Bottom subtle wave
    final wave3Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFCE6D6).withValues(alpha: 0.50),
          const Color(0xFFFBD7C4).withValues(alpha: 0.20),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path3 = Path();
    path3.moveTo(0, h * 0.80);
    path3.cubicTo(w * 0.4, h * 0.73, w * 0.7, h * 0.90, w, h * 0.86);
    path3.lineTo(w, h);
    path3.lineTo(0, h);
    path3.close();
    canvas.drawPath(path3, wave3Paint);

    // Subtle ambient sparkle dots matching screenshot
    final dotPaint = Paint()..color = const Color(0xFFF6C8B2).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(w * 0.25, h * 0.26), 2.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.63, h * 0.25), 2.2, dotPaint);
    canvas.drawCircle(Offset(w * 0.32, h * 0.49), 2.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.55, h * 0.52), 1.8, dotPaint);
    canvas.drawCircle(Offset(w * 0.81, h * 0.30), 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
