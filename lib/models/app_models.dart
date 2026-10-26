import 'dart:convert';

num _num(dynamic value, [num fallback = 0]) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

List<String> _strings(dynamic value) {
  if (value is List) return value.map((e) => e.toString()).toList();
  return const [];
}

class AppUser {
  final String id;
  final String email;
  final String firstName;
  final String lastName;
  final String fullName;
  final String role;
  final String status;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? gender;
  final String? hobbies;
  final bool isTest;

  const AppUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.role,
    required this.status,
    this.phoneNumber,
    this.avatarUrl,
    this.gender,
    this.hobbies,
    this.isTest = false,
  });

  bool get isListener => role == 'EXPERT';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: '${j['id'] ?? ''}',
        email: '${j['email'] ?? ''}',
        firstName: '${j['firstName'] ?? ''}',
        lastName: '${j['lastName'] ?? ''}',
        fullName: '${j['fullName'] ?? '${j['firstName'] ?? ''} ${j['lastName'] ?? ''}'.trim()}',
        role: '${j['role'] ?? 'CUSTOMER'}',
        status: '${j['status'] ?? 'ACTIVE'}',
        phoneNumber: j['phoneNumber']?.toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        gender: j['gender']?.toString(),
        hobbies: j['hobbies']?.toString(),
        isTest: j['isTest'] == true || j['test'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'role': role,
        'status': status,
        'phoneNumber': phoneNumber,
        'avatarUrl': avatarUrl,
        'gender': gender,
        'hobbies': hobbies,
        'isTest': isTest,
      };

  String encode() => jsonEncode(toJson());
}

class ListenerCardModel {
  final String id;
  final String? userId;
  final String displayName;
  final String? avatarUrl;
  final String professionalTitle;
  final String bio;
  final double audioRate;
  final double videoRate;
  final double chatRate;
  final String presence;
  final String? activeSessionType;
  final String? busyDescription;
  final int? busyDurationMinutes;
  final String? lastSeenAt;
  final double rating;
  final int reviewCount;
  final int totalConsultations;
  final List<String> categories;
  final List<String> languages;
  final String? gender;
  final String? hobbies;
  final String? country;
  final bool chatAvailable;
  final bool audioAvailable;
  final bool videoAvailable;
  final bool adultTalkAllowed;
  final bool isTest;

  const ListenerCardModel({
    required this.id,
    this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.professionalTitle,
    required this.bio,
    required this.audioRate,
    required this.videoRate,
    required this.chatRate,
    required this.presence,
    this.activeSessionType,
    this.busyDescription,
    this.busyDurationMinutes,
    this.lastSeenAt,
    required this.rating,
    required this.reviewCount,
    required this.totalConsultations,
    required this.categories,
    required this.languages,
    this.gender,
    this.hobbies,
    this.country,
    this.chatAvailable = true,
    this.audioAvailable = true,
    this.videoAvailable = true,
    this.adultTalkAllowed = false,
    this.isTest = false,
  });

  bool get isOnline => presence == 'ONLINE';
  bool get isBusy => presence == 'BUSY_IN_CALL';
  bool get isOffline => presence == 'OFFLINE' || presence.isEmpty;
  bool get isBusyVideo => (activeSessionType ?? '').toUpperCase().contains('VIDEO');
  bool get isBusyChat => (activeSessionType ?? '').toUpperCase().contains('CHAT');
  bool get isBusyAudio => isBusy && !isBusyVideo && !isBusyChat;
  String get busyLabel => isBusyVideo ? 'Busy in Video Call' : isBusyChat ? 'Busy in Chat' : 'Busy in Voice Call';
  bool get isAdult =>
      adultTalkAllowed ||
      categories.any((c) {
        final s = c.toLowerCase().trim();
        return s == '18+ adult talk' || s == 'adult-talk' || s.contains('adult');
      });

  ListenerCardModel copyWith({
    String? userId,
    String? presence,
    String? activeSessionType,
    String? busyDescription,
    int? busyDurationMinutes,
    String? lastSeenAt,
    String? country,
    bool? chatAvailable,
    bool? audioAvailable,
    bool? videoAvailable,
    bool? adultTalkAllowed,
    bool? isTest,
  }) => ListenerCardModel(
        id: id,
        userId: userId ?? this.userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        professionalTitle: professionalTitle,
        bio: bio,
        audioRate: audioRate,
        videoRate: videoRate,
        chatRate: chatRate,
        presence: presence ?? this.presence,
        activeSessionType: activeSessionType ?? this.activeSessionType,
        busyDescription: busyDescription ?? this.busyDescription,
        busyDurationMinutes: busyDurationMinutes ?? this.busyDurationMinutes,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        rating: rating,
        reviewCount: reviewCount,
        totalConsultations: totalConsultations,
        categories: categories,
        languages: languages,
        gender: gender,
        hobbies: hobbies,
        country: country ?? this.country,
        chatAvailable: chatAvailable ?? this.chatAvailable,
        audioAvailable: audioAvailable ?? this.audioAvailable,
        videoAvailable: videoAvailable ?? this.videoAvailable,
        adultTalkAllowed: adultTalkAllowed ?? this.adultTalkAllowed,
        isTest: isTest ?? this.isTest,
      );

  factory ListenerCardModel.fromJson(Map<String, dynamic> j) {
    final audio = _num(j['audioRatePerMinute'] ?? j['ratePerMinute'], 0).toDouble();
    final video = _num(j['videoRatePerMinute'], audio > 0 ? audio * 1.5 : 0).toDouble();
    final chat = _num(j['chatRatePerMinute'], audio > 0 ? (audio * .6) : 0).toDouble();
    final cats = _strings(j['categories']);
    final bool isAdultVal = j['adultTalkAllowed'] == true ||
        cats.any((c) {
          final s = c.toLowerCase().trim();
          return s == '18+ adult talk' || s == 'adult-talk' || s.contains('adult');
        });
    return ListenerCardModel(
      id: '${j['id'] ?? ''}',
      userId: j['userId']?.toString(),
      displayName: '${j['displayName'] ?? j['name'] ?? 'Listener'}',
      avatarUrl: j['avatarUrl']?.toString(),
      professionalTitle: '${j['professionalTitle'] ?? 'Conversation Listener'}',
      bio: '${j['bio'] ?? ''}',
      audioRate: audio,
      videoRate: video,
      chatRate: chat,
      presence: '${j['presence'] ?? j['presenceStatus'] ?? 'OFFLINE'}',
      activeSessionType: j['activeSessionType']?.toString(),
      busyDescription: j['busyDescription']?.toString(),
      busyDurationMinutes: j['busyDurationMinutes'] != null ? _num(j['busyDurationMinutes']).toInt() : null,
      lastSeenAt: j['lastSeenAt']?.toString(),
      rating: _num(j['ratingAvg'], 0).toDouble(),
      reviewCount: _num(j['reviewCount']).toInt(),
      totalConsultations: _num(j['totalConsultations']).toInt(),
      categories: cats,
      languages: _strings(j['languages']),
      gender: j['gender']?.toString(),
      hobbies: j['hobbies']?.toString(),
      chatAvailable: j['chatAvailable'] != false,
      audioAvailable: j['audioAvailable'] != false,
      videoAvailable: j['videoAvailable'] != false,
      adultTalkAllowed: isAdultVal,
      isTest: j['isTest'] == true || j['test'] == true,
    );
  }
}

class InstantSessionModel {
  final String id;
  final String reference;
  final String status;
  final String type;
  final double ratePerMinute;
  final String? callerId;
  final String callerNickname;
  final String? callerAvatarUrl;
  final String listenerId;
  final String? listenerUserId;
  final String listenerName;
  final String? listenerAvatarUrl;
  final int maxAllowedSeconds;
  final String? requestedAt;
  final String? expiresAt;
  final String? connectedAt;
  final String? startedAt;
  final String? endedAt;
  final int durationSeconds;
  final int billableSeconds;
  final int billableMinutes;
  final double grossAmount;
  final double netListenerEarnings;
  final double giftEarnings;
  final double totalEarnings;
  final double totalAmount;
  final bool hasChatMessages;
  final int chatMessageCount;
  final String? categorySlug;
  final String? notes;
  final bool promotionalBonusUsed;
  final bool isTest;

  const InstantSessionModel({
    required this.id,
    required this.reference,
    required this.status,
    required this.type,
    required this.ratePerMinute,
    this.callerId,
    required this.callerNickname,
    this.callerAvatarUrl,
    required this.listenerId,
    this.listenerUserId,
    required this.listenerName,
    this.listenerAvatarUrl,
    required this.maxAllowedSeconds,
    this.requestedAt,
    this.expiresAt,
    this.connectedAt,
    this.startedAt,
    this.endedAt,
    required this.durationSeconds,
    required this.billableSeconds,
    required this.billableMinutes,
    required this.grossAmount,
    required this.netListenerEarnings,
    required this.giftEarnings,
    required this.totalEarnings,
    required this.totalAmount,
    required this.hasChatMessages,
    required this.chatMessageCount,
    this.categorySlug,
    this.notes,
    this.promotionalBonusUsed = false,
    this.isTest = false,
  });

  bool get isChat => type == 'CHAT';
  bool get isVideo => type == 'VIDEO_CALL';
  bool get ended => const {'COMPLETED', 'CANCELLED', 'REJECTED', 'EXPIRED', 'TERMINATED'}.contains(status) || (endedAt != null && endedAt!.isNotEmpty);
  bool get isLive => const {'ACCEPTED', 'CONNECTING', 'CONNECTED', 'ACTIVE'}.contains(status);
  bool get isCompleted => status == 'COMPLETED';
  bool get isMissed => const {'CANCELLED', 'EXPIRED', 'REJECTED'}.contains(status);

  double get effectiveListenerEarnings {
    if (totalEarnings > 0) return totalEarnings;
    if (netListenerEarnings > 0) return netListenerEarnings + giftEarnings;
    if (isCompleted) {
      if (grossAmount > 0) return (grossAmount * 0.5) + giftEarnings;
      if (billableMinutes > 0 && ratePerMinute > 0) return (billableMinutes * ratePerMinute * 0.5) + giftEarnings;
    }
    if (isLive && ratePerMinute > 0) {
      final start = DateTime.tryParse(connectedAt ?? startedAt ?? requestedAt ?? '')?.toLocal();
      if (start != null) {
        final elapsedMins = (DateTime.now().difference(start).inSeconds / 60.0).ceil().clamp(1, 9999);
        return (elapsedMins * ratePerMinute * 0.5) + giftEarnings;
      }
    }
    return giftEarnings;
  }

  factory InstantSessionModel.fromJson(Map<String, dynamic> j) => InstantSessionModel(
        id: '${j['id'] ?? ''}',
        reference: '${j['sessionReference'] ?? ''}',
        status: '${j['status'] ?? ''}',
        type: '${j['sessionType'] ?? j['type'] ?? 'AUDIO_CALL'}',
        ratePerMinute: _num(j['ratePerMinute']).toDouble(),
        callerId: j['callerId']?.toString(),
        callerNickname: '${j['callerNickname'] ?? 'Anonymous Caller'}',
        callerAvatarUrl: j['callerAvatarUrl']?.toString(),
        listenerId: '${j['listenerId'] ?? ''}',
        listenerUserId: j['listenerUserId']?.toString(),
        listenerName: '${j['listenerName'] ?? 'Listener'}',
        listenerAvatarUrl: j['listenerAvatarUrl']?.toString(),
        maxAllowedSeconds: _num(j['maxAllowedSeconds']).toInt(),
        requestedAt: j['requestedAt']?.toString(),
        expiresAt: j['expiresAt']?.toString(),
        connectedAt: j['connectedAt']?.toString(),
        startedAt: j['startedAt']?.toString(),
        endedAt: j['endedAt']?.toString(),
        durationSeconds: _num(j['durationSeconds'] ?? j['billableSeconds']).toInt(),
        billableSeconds: _num(j['billableSeconds']).toInt(),
        billableMinutes: _num(j['billableMinutes']).toInt(),
        grossAmount: _num(j['grossAmount'] ?? j['totalAmount']).toDouble(),
        netListenerEarnings: _num(j['netListenerEarnings']).toDouble(),
        giftEarnings: _num(j['giftEarnings']).toDouble(),
        totalEarnings: _num(j['totalEarnings']).toDouble(),
        totalAmount: _num(j['totalAmount'] ?? j['grossAmount']).toDouble(),
        hasChatMessages: j['hasChatMessages'] == true,
        chatMessageCount: _num(j['chatMessageCount']).toInt(),
        categorySlug: j['categorySlug']?.toString(),
        notes: j['notes']?.toString(),
        promotionalBonusUsed: j['promotionalBonusUsed'] == true,
      );
}

class WalletModel {
  final String walletId;
  final double balance;
  final double bonusBalance;
  final double totalBalance;
  final String currency;
  final String formattedBalance;

  const WalletModel({required this.walletId, required this.balance, required this.bonusBalance, required this.totalBalance, required this.currency, required this.formattedBalance});

  factory WalletModel.fromJson(Map<String, dynamic> j) => WalletModel(
        walletId: '${j['walletId'] ?? ''}',
        balance: _num(j['balance']).toDouble(),
        bonusBalance: _num(j['bonusBalance']).toDouble(),
        totalBalance: _num(j['totalBalance'], _num(j['balance']) + _num(j['bonusBalance'])).toDouble(),
        currency: '${j['currency'] ?? 'INR'}',
        formattedBalance: '${j['formattedBalance'] ?? '₹${_num(j['totalBalance']).toStringAsFixed(2)}'}',
      );
}

class AnonymousProfileModel {
  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final int totalCallsTaken;
  final int totalCallsMade;
  final double rating;

  const AnonymousProfileModel({required this.id, required this.nickname, this.avatarUrl, this.bio, required this.totalCallsTaken, required this.totalCallsMade, required this.rating});

  factory AnonymousProfileModel.fromJson(Map<String, dynamic> j) => AnonymousProfileModel(
        id: '${j['id'] ?? ''}',
        nickname: '${j['nickname'] ?? 'Anonymous'}',
        avatarUrl: j['avatarUrl']?.toString(),
        bio: j['bio']?.toString(),
        totalCallsTaken: _num(j['totalCallsTaken']).toInt(),
        totalCallsMade: _num(j['totalCallsMade']).toInt(),
        rating: _num(j['ratingAvg']).toDouble(),
      );
}

class BookingModel {
  final String id;
  final String bookingReference;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String expertId;
  final String expertName;
  final String expertTitle;
  final DateTime? startTime;
  final DateTime? endTime;
  final int durationMinutes;
  final String consultationType;
  final String agenda;
  final String status;
  final double holdAmount;
  final double capturedAmount;
  final String currency;
  final String? meetingRoomUrl;
  final DateTime? createdAt;

  const BookingModel({
    required this.id,
    required this.bookingReference,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.expertId,
    required this.expertName,
    required this.expertTitle,
    this.startTime,
    this.endTime,
    required this.durationMinutes,
    required this.consultationType,
    required this.agenda,
    required this.status,
    required this.holdAmount,
    required this.capturedAmount,
    required this.currency,
    this.meetingRoomUrl,
    this.createdAt,
  });

  bool get isJoinable => const {'ACCEPTED', 'IN_PROGRESS'}.contains(status);
  bool get isCompleted => status == 'COMPLETED';

  factory BookingModel.fromJson(Map<String, dynamic> j) => BookingModel(
        id: '${j['id'] ?? ''}',
        bookingReference: '${j['bookingReference'] ?? ''}',
        customerId: '${j['customerId'] ?? ''}',
        customerName: '${j['customerName'] ?? ''}',
        customerEmail: '${j['customerEmail'] ?? ''}',
        expertId: '${j['expertId'] ?? ''}',
        expertName: '${j['expertName'] ?? 'Listener'}',
        expertTitle: '${j['expertTitle'] ?? ''}',
        startTime: DateTime.tryParse('${j['startTime'] ?? ''}'),
        endTime: DateTime.tryParse('${j['endTime'] ?? ''}'),
        durationMinutes: _num(j['durationMinutes']).toInt(),
        consultationType: '${j['consultationType'] ?? 'AUDIO'}',
        agenda: '${j['agenda'] ?? ''}',
        status: '${j['status'] ?? ''}',
        holdAmount: _num(j['holdAmount']).toDouble(),
        capturedAmount: _num(j['capturedAmount']).toDouble(),
        currency: '${j['currency'] ?? 'INR'}',
        meetingRoomUrl: j['meetingRoomUrl']?.toString(),
        createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
      );
}

class CallTokenModel {
  final String callId;
  final String bookingId;
  final String roomId;
  final String roomUrl;
  final String token;
  final bool isOwner;
  final String participantName;
  final String consultationType;
  final DateTime? scheduledStartTime;
  final DateTime? scheduledEndTime;
  final int durationMinutes;

  const CallTokenModel({
    required this.callId,
    required this.bookingId,
    required this.roomId,
    required this.roomUrl,
    required this.token,
    required this.isOwner,
    required this.participantName,
    required this.consultationType,
    this.scheduledStartTime,
    this.scheduledEndTime,
    required this.durationMinutes,
  });

  factory CallTokenModel.fromJson(Map<String, dynamic> j) => CallTokenModel(
        callId: '${j['callId'] ?? ''}',
        bookingId: '${j['bookingId'] ?? ''}',
        roomId: '${j['roomId'] ?? ''}',
        roomUrl: '${j['roomUrl'] ?? ''}',
        token: '${j['token'] ?? ''}',
        isOwner: j['isOwner'] == true,
        participantName: '${j['participantName'] ?? ''}',
        consultationType: '${j['consultationType'] ?? 'AUDIO'}',
        scheduledStartTime: DateTime.tryParse('${j['scheduledStartTime'] ?? ''}'),
        scheduledEndTime: DateTime.tryParse('${j['scheduledEndTime'] ?? ''}'),
        durationMinutes: _num(j['durationMinutes']).toInt(),
      );
}

class CallStatusModel {
  final String callId;
  final String bookingId;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int elapsedSeconds;
  final int billableMinutes;
  final double currentCost;
  final String currency;
  final bool isConnected;
  final int? remainingSeconds;

  const CallStatusModel({
    required this.callId,
    required this.bookingId,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.elapsedSeconds,
    required this.billableMinutes,
    required this.currentCost,
    required this.currency,
    required this.isConnected,
    this.remainingSeconds,
  });

  factory CallStatusModel.fromJson(Map<String, dynamic> j) => CallStatusModel(
        callId: '${j['callId'] ?? ''}',
        bookingId: '${j['bookingId'] ?? ''}',
        status: '${j['status'] ?? ''}',
        startedAt: DateTime.tryParse('${j['startedAt'] ?? ''}'),
        endedAt: DateTime.tryParse('${j['endedAt'] ?? ''}'),
        elapsedSeconds: _num(j['elapsedSeconds']).toInt(),
        billableMinutes: _num(j['billableMinutes']).toInt(),
        currentCost: _num(j['currentCost']).toDouble(),
        currency: '${j['currency'] ?? 'INR'}',
        isConnected: j['isConnected'] == true,
        remainingSeconds: j['remainingSeconds'] == null ? null : _num(j['remainingSeconds']).toInt(),
      );
}

class RecordingGovernanceModel {
  final bool audioRecordingEnabled;
  final bool videoRecordingEnabled;
  final bool chatRecordingEnabled;
  final bool blockScreenshotsEnabled;
  final bool blockScreenRecordingEnabled;

  const RecordingGovernanceModel({
    required this.audioRecordingEnabled,
    required this.videoRecordingEnabled,
    required this.chatRecordingEnabled,
    required this.blockScreenshotsEnabled,
    required this.blockScreenRecordingEnabled,
  });

  factory RecordingGovernanceModel.fromJson(Map<String, dynamic> j) => RecordingGovernanceModel(
        audioRecordingEnabled: j['audioRecordingEnabled'] != false,
        videoRecordingEnabled: j['videoRecordingEnabled'] != false,
        chatRecordingEnabled: j['chatRecordingEnabled'] != false,
        blockScreenshotsEnabled: j['blockScreenshotsEnabled'] != false,
        blockScreenRecordingEnabled: j['blockScreenRecordingEnabled'] != false,
      );
}
