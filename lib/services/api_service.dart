import 'dart:io';
import '../core/api_client.dart';
import '../models/app_models.dart';

class ApiService {
  final ApiClient client;
  ApiService(this.client);

  List<dynamic> _content(dynamic value) {
    if (value is List) return value;
    if (value is Map && value['content'] is List) return value['content'] as List;
    return const [];
  }

  Future<Map<String, dynamic>> login(String email, String password) async =>
      Map<String, dynamic>.from(await client.post('/auth/login', body: {'email': email, 'password': password}));

  Future<Map<String, dynamic>> registerListener(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.post('/auth/register', body: data));

  Future<Map<String, dynamic>> verifyGovtId({
    required String idType,
    required String idNumber,
    String? name,
    String? state,
    String? country,
  }) async =>
      Map<String, dynamic>.from(await client.post('/auth/verify-id', body: {
        'idType': idType,
        'idNumber': idNumber,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (state != null && state.trim().isNotEmpty) 'state': state.trim(),
        if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
      }));

  Future<Map<String, dynamic>> googleLogin(String idToken) async =>
      Map<String, dynamic>.from(await client.post('/auth/google', body: {'idToken': idToken, 'accountType': 'CALLER'}));

  Future<void> sendOtp(String mobile) async => client.post('/auth/send-otp', body: {'mobileNumber': mobile});

  Future<Map<String, dynamic>> verifyOtp(String mobile, String otp) async =>
      Map<String, dynamic>.from(await client.post('/auth/verify-otp', body: {'mobileNumber': mobile, 'otp': otp}));

  Future<Map<String, dynamic>> firebaseOtpLogin(String idToken, [String? mobileNumber]) async =>
      Map<String, dynamic>.from(await client.post('/auth/firebase-otp', body: {
        'idToken': idToken,
        if (mobileNumber != null && mobileNumber.trim().isNotEmpty) 'mobileNumber': mobileNumber.trim(),
      }));

  Future<void> forgotPassword(String identifier) async => client.post('/auth/forgot-password', body: {
        'identifier': identifier,
        'channel': identifier.contains('@') ? 'EMAIL' : 'MOBILE',
      });

  Future<void> resetPassword(String identifier, String code, String newPassword) async =>
      client.post('/auth/reset-password', body: {'identifier': identifier, 'code': code, 'newPassword': newPassword});

  Future<Map<String, dynamic>> brandGovernance() async =>
      Map<String, dynamic>.from(await client.get('/config/brand-governance'));

  Future<Map<String, dynamic>> authGovernance() async =>
      Map<String, dynamic>.from(await client.get('/config/auth-governance'));

  Future<Map<String, dynamic>> inactivityGovernance() async =>
      Map<String, dynamic>.from(await client.get('/config/inactivity-governance'));

  Future<Map<String, dynamic>> legalPolicies() async =>
      Map<String, dynamic>.from(await client.get('/config/legal-policies'));

  Future<AppUser> me() async => AppUser.fromJson(Map<String, dynamic>.from(await client.get('/auth/me')));

  Future<AppUser> updateUserProfile(Map<String, dynamic> data) async =>
      AppUser.fromJson(Map<String, dynamic>.from(await client.put('/auth/profile', body: data)));

  final Map<String, bool> _blockedByTargetCache = <String, bool>{};
  final Map<String, DateTime> _blockedByTargetCheckedAt = <String, DateTime>{};

  Future<Set<String>> blockedByMeIds() async {
    if (client.token == null || client.token!.isEmpty) return <String>{};
    try {
      final raw = _content(await client.get('/safety/blocked-by-me'));
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toSet();
    } catch (_) {
      // Older backend fallback.
      try {
        final raw = _content(await client.get('/safety/blocks'));
        final out = <String>{};
        for (final item in raw) {
          if (item is String && item.isNotEmpty) {
            out.add(item);
          } else if (item is Map) {
            final v = item['blockedUserId']?.toString() ?? item['blockedId']?.toString();
            if (v != null && v.isNotEmpty) out.add(v);
          }
        }
        return out;
      } catch (_) {
        return <String>{};
      }
    }
  }

  Set<String>? _cachedBlockedMe;
  DateTime? _cachedBlockedMeAt;

  Future<Set<String>> blockedMeIds() async {
    if (client.token == null || client.token!.isEmpty) return <String>{};
    if (_cachedBlockedMe != null &&
        _cachedBlockedMeAt != null &&
        DateTime.now().difference(_cachedBlockedMeAt!) < const Duration(seconds: 45)) {
      return _cachedBlockedMe!;
    }
    try {
      final res = await client.get('/safety/blocked-me');
      final out = <String>{};
      for (final item in _content(res)) {
        if (item != null) out.add(item.toString());
      }
      _cachedBlockedMe = out;
      _cachedBlockedMeAt = DateTime.now();
      return out;
    } catch (_) {
      return _cachedBlockedMe ?? <String>{};
    }
  }

  Future<bool> amIBlockedBy(String targetUserId, {bool force = false}) async {
    if (targetUserId.isEmpty || client.token == null || client.token!.isEmpty) return false;
    final last = _blockedByTargetCheckedAt[targetUserId];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 45)) {
      return _blockedByTargetCache[targetUserId] ?? false;
    }
    try {
      final m = Map<String, dynamic>.from(await client.get('/safety/am-i-blocked-by/$targetUserId'));
      final blocked = m['blocked'] == true;
      _blockedByTargetCache[targetUserId] = blocked;
      _blockedByTargetCheckedAt[targetUserId] = DateTime.now();
      return blocked;
    } catch (_) {
      return _blockedByTargetCache[targetUserId] ?? false;
    }
  }

  Future<List<ListenerCardModel>> _decorateAndHideBlocked(dynamic listenerData, [List<dynamic>? expertCards]) async {
    final userIds = <String, String>{};
    if (expertCards != null && expertCards.isNotEmpty) {
      for (final item in expertCards) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final uid = item['userId']?.toString() ?? '';
        if (id.isNotEmpty && uid.isNotEmpty) userIds[id] = uid;
      }
    }

    var listeners = _content(listenerData)
        .map((e) => ListenerCardModel.fromJson(Map<String, dynamic>.from(e)))
        .map((e) => e.copyWith(userId: e.userId ?? userIds[e.id]))
        .toList();

    if (client.token == null || client.token!.isEmpty || listeners.isEmpty) return listeners;

    // Concurrently fetch blockedByMe and blockedMe in just 2 quick requests instead of 50 parallel calls!
    final blockResults = await Future.wait<Set<String>>([
      blockedByMeIds(),
      blockedMeIds(),
    ]);
    final blockedByMe = blockResults[0];
    final blockedMe = blockResults[1];

    return listeners.where((e) {
      final uid = e.userId;
      if (uid == null || uid.isEmpty) return true;
      return !blockedByMe.contains(uid) && !blockedMe.contains(uid);
    }).toList();
  }

  Future<List<ListenerCardModel>> onlineListeners({bool includeOffline = true, String? category}) async {
    final data = await client.get('/listeners/online', query: {
      'includeOffline': includeOffline,
      if (category?.isNotEmpty == true) 'categorySlug': category,
    });
    return _decorateAndHideBlocked(data);
  }

  Future<List<ListenerCardModel>> allListeners({
    String? query,
    String? category,
    double? minRating,
    double? maxRate,
  }) async {
    final data = await client.get('/listeners/all', query: {
      if (query?.isNotEmpty == true) 'query': query,
      if (category?.isNotEmpty == true) 'categorySlug': category,
    });
    var all = await _decorateAndHideBlocked(data);
    if (minRating != null) all = all.where((e) => e.rating >= minRating).toList();
    if (maxRate != null) all = all.where((e) => e.audioRate <= maxRate).toList();
    return all;
  }

  Future<Map<String, dynamic>> expertDetail(String id) async =>
      Map<String, dynamic>.from(await client.get('/experts/$id'));

  Future<Map<String, dynamic>> myExpertProfile() async =>
      Map<String, dynamic>.from(await client.get('/experts/me'));

  Future<Map<String, dynamic>> updateExpertProfile(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.put('/experts/profile', body: data));

  Future<Map<String, dynamic>> submitExpertVerification() async =>
      Map<String, dynamic>.from(await client.post('/experts/submit-verification'));

  Future<List<dynamic>> categories() async => _content(await client.get('/categories'));
  Future<List<dynamic>> languages() async => _content(await client.get('/languages'));
  Future<List<dynamic>> skills([String? categoryId]) async => _content(await client.get('/skills', query: {if (categoryId != null) 'categoryId': categoryId}));

  Future<WalletModel> wallet() async => WalletModel.fromJson(Map<String, dynamic>.from(await client.get('/wallet')));
  Future<List<dynamic>> walletTransactions({int page = 0, int size = 50}) async => _content(await client.get('/wallet/transactions', query: {'page': page, 'size': size}));
  Future<Map<String, dynamic>> createRecharge(double amount) async => Map<String, dynamic>.from(await client.post('/wallet/recharge/create-order', body: {'amount': amount}));
  Future<WalletModel> verifyRecharge(Map<String, dynamic> data) async => WalletModel.fromJson(Map<String, dynamic>.from(await client.post('/wallet/recharge/verify', body: data)));

  Future<AnonymousProfileModel> anonymousProfile() async =>
      AnonymousProfileModel.fromJson(Map<String, dynamic>.from(await client.get('/user/anonymous-profile')));
  Future<AnonymousProfileModel> updateAnonymousProfile(Map<String, dynamic> data) async =>
      AnonymousProfileModel.fromJson(Map<String, dynamic>.from(await client.put('/user/anonymous-profile', body: data)));
  Future<AnonymousProfileModel> regenerateNickname() async =>
      AnonymousProfileModel.fromJson(Map<String, dynamic>.from(await client.post('/user/anonymous-profile/regenerate-nickname')));

  Future<Map<String, dynamic>> uploadAvatar(File file) async => client.multipart('/media/avatar', file: file);
  Future<Map<String, dynamic>> uploadMedia(File file, {String folder = 'uploads'}) async =>
      client.multipart('/media/upload', file: file, fields: {'folder': folder});

  Future<Map<String, dynamic>> follow(String listenerId) async => Map<String, dynamic>.from(await client.post('/listeners/$listenerId/follow'));
  Future<Map<String, dynamic>> unfollow(String listenerId) async => Map<String, dynamic>.from(await client.delete('/listeners/$listenerId/follow'));
  Future<Map<String, dynamic>> followingStatus(String listenerId) async => Map<String, dynamic>.from(await client.get('/listeners/$listenerId/is-following'));
  Future<List<dynamic>> followedListeners() async => _content(await client.get('/listeners/following'));
  Future<Map<String, dynamic>> nudge(String listenerId) async => Map<String, dynamic>.from(await client.post('/listeners/$listenerId/nudge'));

  Future<InstantSessionModel> requestSession(String listenerId, String type, {String? categorySlug}) async =>
      InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/instant-request', body: {
        'listenerId': listenerId,
        'sessionType': type,
        if (categorySlug != null) 'categorySlug': categorySlug,
      })));

  Future<InstantSessionModel?> pendingListenerSession() async {
    final data = await client.get('/sessions/listener-pending');
    if (data == null) return null;
    return InstantSessionModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<InstantSessionModel> acceptSession(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/accept')));
  Future<InstantSessionModel> rejectSession(String id, [String? reason]) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/reject', body: {'reason': reason})));
  Future<InstantSessionModel> callbackSession(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/callback')));
  Future<InstantSessionModel> startSession(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/start')));
  Future<void> sessionHeartbeat(String id) async => client.post('/sessions/$id/heartbeat');
  Future<InstantSessionModel> endSession(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/end')));
  Future<InstantSessionModel> cancelSession(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.post('/sessions/$id/cancel')));
  Future<InstantSessionModel> session(String id) async => InstantSessionModel.fromJson(Map<String, dynamic>.from(await client.get('/sessions/$id')));
  Future<List<InstantSessionModel>> callerHistory() async => _content(await client.get('/sessions/caller-history')).map((e) => InstantSessionModel.fromJson(Map<String, dynamic>.from(e))).toList();
  Future<List<InstantSessionModel>> listenerHistory() async {
    final list = _content(await client.get('/sessions/listener-history'))
        .map((e) => InstantSessionModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (list.isEmpty) {
      try {
        final callerList = _content(await client.get('/sessions/caller-history'))
            .map((e) => InstantSessionModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (callerList.isNotEmpty) return callerList;
      } catch (_) {}
    }
    return list;
  }

  Future<List<dynamic>> messages(String sessionId) async => _content(await client.get('/sessions/$sessionId/messages'));
  Future<Map<String, dynamic>> sendMessage(String sessionId, String text, {required String senderName, required String senderRole}) async =>
      Map<String, dynamic>.from(await client.post('/sessions/$sessionId/messages', body: {'text': text, 'senderName': senderName, 'senderRole': senderRole}));

  List<Map<String, dynamic>>? _cachedIceServers;
  Future<List<Map<String, dynamic>>> iceServers({bool forceRefresh = false}) async {
    if (_cachedIceServers != null && !forceRefresh) return _cachedIceServers!;
    try {
      final data = _content(await client.get('/webrtc/ice-servers'));
      final list = data.map((e) => Map<String, dynamic>.from(e)).toList();
      _cachedIceServers = list;
      return list;
    } catch (_) {
      return [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302',
            'stun:stun3.l.google.com:19302',
            'stun:stun4.l.google.com:19302',
          ]
        },
        {
          'urls': ['stun:stun.cloudflare.com:3478']
        }
      ];
    }
  }
  Future<List<dynamic>> signals(String sessionId, [int? since]) async => _content(await client.get('/webrtc/sessions/$sessionId/signals', query: {if (since != null) 'since': since}));
  Future<void> sendSignal(String sessionId, Map<String, dynamic> data) async => client.post('/webrtc/sessions/$sessionId/signal', body: data);

  Future<List<dynamic>> gifts() async => _content(await client.get('/gifts'));
  Future<Map<String, dynamic>> sendGift(String sessionId, String giftType, {String? note}) async => Map<String, dynamic>.from(await client.post('/gifts/send', body: {'sessionId': sessionId, 'giftType': giftType, if (note != null) 'note': note}));
  Future<List<dynamic>> sessionGifts(String sessionId) async => _content(await client.get('/gifts/session/$sessionId'));

  Future<List<dynamic>> notifications({int page = 0, int size = 50}) async => _content(await client.get('/notifications', query: {'page': page, 'size': size}));
  Future<int> unreadCount() async {
    final m = Map<String, dynamic>.from(await client.get('/notifications/unread-count'));
    return (m['unreadCount'] as num?)?.toInt() ?? 0;
  }
  Future<void> readNotification(String id) async => client.patch('/notifications/$id/read');
  Future<void> readAllNotifications() async => client.patch('/notifications/read-all');
  Future<void> clearNotifications() async => client.delete('/notifications');

  Future<void> reportUser(String reportedUserId, {String? sessionId, required String reason, String? description}) async =>
      client.post('/safety/report', body: {'reportedUserId': reportedUserId, if (sessionId != null) 'sessionId': sessionId, 'reason': reason, if (description != null) 'description': description});
  Future<void> blockUser(String id, {String? reason, String? targetName, String? targetRole}) async => client.post('/safety/block', body: {
        'blockedUserId': id,
        if (reason != null) 'reason': reason,
        if (targetName != null) 'targetName': targetName,
        if (targetRole != null) 'targetRole': targetRole,
      });
  Future<void> unblockUser(String id) async => client.post('/safety/unblock/$id');
  Future<List<dynamic>> blockedUsers() async => _content(await client.get('/safety/blocks'));
  Future<List<dynamic>> blockHistory() async => _content(await client.get('/safety/my-block-history'));

  Future<List<dynamic>> inquiries() async => _content(await client.get('/safety/inquiries/mine'));
  Future<Map<String, dynamic>> submitInquiry(Map<String, dynamic> data) async => Map<String, dynamic>.from(await client.post('/safety/inquiries', body: data));
  Future<Map<String, dynamic>> submitContact(Map<String, dynamic> data) async => Map<String, dynamic>.from(await client.post('/contact', body: data));

  Future<Map<String, dynamic>> updatePresence(String status) async => Map<String, dynamic>.from(await client.post('/listeners/presence', body: {'status': status}));
  Future<Map<String, dynamic>> presenceHeartbeat() async => Map<String, dynamic>.from(await client.post('/listeners/presence/heartbeat'));
  Future<Map<String, dynamic>> updateModalities({bool? chatAvailable, bool? audioAvailable, bool? videoAvailable}) async {
    final body = <String, dynamic>{};
    if (chatAvailable != null) body['chatAvailable'] = chatAvailable;
    if (audioAvailable != null) body['audioAvailable'] = audioAvailable;
    if (videoAvailable != null) body['videoAvailable'] = videoAvailable;
    return Map<String, dynamic>.from(await client.post('/listeners/availability/modalities', body: body));
  }
  Future<Map<String, dynamic>> listenerAttendance() async => Map<String, dynamic>.from(await client.get('/listeners/attendance'));
  Future<List<Map<String, dynamic>>> listenerAttendanceHistory({String? from, String? to}) async {
    final query = <String, dynamic>{};
    if (from != null) query['from'] = from;
    if (to != null) query['to'] = to;
    final res = await client.get('/listeners/attendance/history', query: query.isNotEmpty ? query : null);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<List<dynamic>> payoutHistory() async => _content(await client.get('/listener/payouts'));
  Future<Map<String, dynamic>> getTdsEstimate(double amount) async =>
      Map<String, dynamic>.from(await client.get('/listener/payouts/tds-estimate', query: {'amount': amount.toString()}));

  Future<Map<String, dynamic>> requestPayout(double amount, String vpa, {String? notes, String? panNumber}) async =>
      Map<String, dynamic>.from(await client.post('/listener/payouts/request-upi', body: {
        'amount': amount,
        'vpa': vpa,
        if (notes != null) 'notes': notes,
        if (panNumber != null && panNumber.isNotEmpty) 'panNumber': panNumber,
      }));

  Future<List<dynamic>> expertReviews(String expertId, {int page = 0, int size = 50}) async => _content(await client.get('/reviews/expert/$expertId', query: {'page': page, 'size': size}));
  Future<Map<String, dynamic>> createReview({String? sessionId, String? bookingId, required int rating, String? comment}) async =>
      Map<String, dynamic>.from(await client.post('/reviews', body: {
        if (sessionId != null) 'sessionId': sessionId,
        if (bookingId != null) 'bookingId': bookingId,
        'rating': rating,
        if (comment != null) 'comment': comment,
      }));
  Future<Map<String, dynamic>> respondToReview(String reviewId, String response) async => Map<String, dynamic>.from(await client.post('/reviews/$reviewId/response', body: {'response': response}));

  Future<List<dynamic>> availableSlots(String expertId, String date, String tz, {int? duration}) async => _content(await client.get('/experts/$expertId/availability', query: {'date': date, 'tz': tz, if (duration != null) 'duration': duration}));
  Future<void> configureAvailability(List<Map<String, dynamic>> rules) async => client.post('/expert/availability/rules', body: {'rules': rules});
  Future<void> addAvailabilityException(Map<String, dynamic> data) async => client.post('/expert/availability/exceptions', body: data);

  Future<Map<String, dynamic>> nudgeStatus(String listenerId) async =>
      Map<String, dynamic>.from(await client.get('/listeners/$listenerId/nudge-status'));

  Future<List<BookingModel>> customerBookings({int page = 0, int size = 50}) async =>
      _content(await client.get('/bookings/customer', query: {'page': page, 'size': size}))
          .map((e) => BookingModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  Future<List<BookingModel>> expertBookings({int page = 0, int size = 50}) async =>
      _content(await client.get('/bookings/expert', query: {'page': page, 'size': size}))
          .map((e) => BookingModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

  Future<BookingModel> booking(String id) async =>
      BookingModel.fromJson(Map<String, dynamic>.from(await client.get('/bookings/$id')));

  Future<BookingModel> createBooking({
    required String expertId,
    required String startTime,
    required int durationMinutes,
    required String consultationType,
    String agenda = '',
  }) async => BookingModel.fromJson(Map<String, dynamic>.from(await client.post('/bookings', body: {
        'expertId': expertId,
        'startTime': startTime,
        'durationMinutes': durationMinutes,
        'consultationType': consultationType,
        'agenda': agenda,
      })));

  Future<BookingModel> cancelBooking(String id, String reason) async =>
      BookingModel.fromJson(Map<String, dynamic>.from(await client.post('/bookings/$id/cancel', body: {'reason': reason})));

  Future<Map<String, dynamic>> createDispute({required String bookingId, required String reason, required String description}) async =>
      Map<String, dynamic>.from(await client.post('/disputes', body: {'bookingId': bookingId, 'reason': reason, 'description': description}));

  Future<List<dynamic>> myDisputes({int page = 0, int size = 50}) async =>
      _content(await client.get('/disputes/my', query: {'page': page, 'size': size}));

  Future<CallTokenModel> callToken(String bookingId) async =>
      CallTokenModel.fromJson(Map<String, dynamic>.from(await client.post('/calls/$bookingId/token')));

  Future<CallStatusModel> callStatus(String bookingId) async =>
      CallStatusModel.fromJson(Map<String, dynamic>.from(await client.get('/calls/$bookingId/status')));

  Future<void> recordCallConnected(String bookingId) async => client.post('/calls/$bookingId/connect');
  Future<void> endBookingCall(String bookingId) async => client.post('/calls/$bookingId/end');

  Future<Map<String, dynamic>> rateLimits() async =>
      Map<String, dynamic>.from(await client.get('/config/rate-limits'));

  Future<RecordingGovernanceModel> recordingGovernance() async =>
      RecordingGovernanceModel.fromJson(Map<String, dynamic>.from(await client.get('/config/recording-governance')));

  Future<Map<String, dynamic>> logInterceptionAudit(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(await client.post('/recording-governance/audit', body: data));

  Future<void> auditTranscript(String sessionId, String transcript) async => client.post('/safety/audit-transcript', body: {'sessionId': sessionId, 'transcript': transcript});
  Future<void> securityAlert(String sessionId, String type, [String? details]) async => client.post('/safety/security-alert', body: {'sessionId': sessionId, 'alertType': type, if (details != null) 'details': details});

  Future<Map<String, dynamic>> uploadRecording(String sessionId, File file) async =>
      client.multipart('/sessions/$sessionId/recording', file: file);
  Future<void> reportNudityIncident({
    required String sessionId,
    String? userId,
    String? userName,
    String? userRole,
    String? peerId,
    String? peerName,
    required String detectedSource,
    String? classificationLabel,
    double? confidenceScore,
    double? skinRatio,
    String? actionTaken,
    bool? isNudityAllowed,
    String? snapshotData,
  }) async {
    await client.post('/safety/nudity-incident', body: {
      'sessionId': sessionId,
      if (userId != null) 'userId': userId,
      if (userName != null) 'userName': userName,
      if (userRole != null) 'userRole': userRole,
      if (peerId != null) 'peerId': peerId,
      if (peerName != null) 'peerName': peerName,
      'detectedSource': detectedSource,
      if (classificationLabel != null) 'classificationLabel': classificationLabel,
      if (confidenceScore != null) 'confidenceScore': confidenceScore,
      if (skinRatio != null) 'skinRatio': skinRatio,
      if (actionTaken != null) 'actionTaken': actionTaken,
      if (isNudityAllowed != null) 'isNudityAllowed': isNudityAllowed,
      if (snapshotData != null) 'snapshotData': snapshotData,
    });
  }
}
