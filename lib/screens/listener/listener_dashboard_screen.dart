import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../session/session_screen.dart';
import 'listener_peers_screen.dart';
import 'listener_reviews_screen.dart';

class ListenerDashboardScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;
  const ListenerDashboardScreen({super.key, this.onNavigateTab});

  @override
  State<ListenerDashboardScreen> createState() => _ListenerDashboardScreenState();
}

class _ListenerDashboardScreenState extends State<ListenerDashboardScreen> {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? attendance;
  WalletModel? wallet;
  List<InstantSessionModel> sessions = [];
  final Set<String> dismissedMissed = <String>{};
  bool loading = true;
  String presence = 'OFFLINE';
  String? activeSessionType;
  int liveOnlineSeconds = 0;
  bool chatAvailable = true;
  bool audioAvailable = true;
  bool videoAvailable = true;
  bool modalityBusy = false;
  int selectedSubTab = 0; // 0: Calls & Chats, 1: Attendance, 2: Transactions, 3: Earnings, 4: Gifts, 5: UPI
  Timer? heartbeat;
  Timer? refresh;
  Timer? ticker;

  // Curated theme colors for the warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color cardBg = Colors.white;
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color emeraldOnline = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _load();
    heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => _beat());
    refresh = Timer.periodic(const Duration(seconds: 8), (_) => _load(silent: true));
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && presence == 'ONLINE') setState(() => liveOnlineSeconds++);
    });
  }

  @override
  void dispose() {
    heartbeat?.cancel();
    refresh?.cancel();
    ticker?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final api = context.read<AppController>().api;
      final results = await Future.wait<dynamic>([
        api.myExpertProfile(),
        api.listenerAttendance(),
        api.wallet(),
        api.listenerHistory(),
      ]);
      if (!mounted) return;
      final p = Map<String, dynamic>.from(results[0] as Map);
      final a = Map<String, dynamic>.from(results[1] as Map);
      setState(() {
        profile = p;
        attendance = a;
        wallet = results[2] as WalletModel;
        sessions = results[3] as List<InstantSessionModel>;
        presence = '${p['presence'] ?? p['presenceStatus'] ?? a['presence'] ?? 'OFFLINE'}';
        activeSessionType = p['activeSessionType']?.toString();
        liveOnlineSeconds = (a['onlineSeconds'] as num?)?.toInt() ?? liveOnlineSeconds;
        chatAvailable = p['chatAvailable'] != false;
        audioAvailable = p['audioAvailable'] != false;
        videoAvailable = p['videoAvailable'] != false;
        loading = false;
      });
      if (mounted) {
        context.read<AppController>().updatePresence(presence);
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _toggleModality(String modality) async {
    final nextChat = modality == 'chat' ? !chatAvailable : chatAvailable;
    final nextAudio = modality == 'audio' ? !audioAvailable : audioAvailable;
    final nextVideo = modality == 'video' ? !videoAvailable : videoAvailable;
    setState(() {
      chatAvailable = nextChat;
      audioAvailable = nextAudio;
      videoAvailable = nextVideo;
      modalityBusy = true;
    });
    try {
      final res = await context.read<AppController>().api.updateModalities(
        chatAvailable: nextChat,
        audioAvailable: nextAudio,
        videoAvailable: nextVideo,
      );
      if (!mounted) return;
      setState(() {
        chatAvailable = res['chatAvailable'] != false;
        audioAvailable = res['audioAvailable'] != false;
        videoAvailable = res['videoAvailable'] != false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (modality == 'chat') chatAvailable = !nextChat;
        if (modality == 'audio') audioAvailable = !nextAudio;
        if (modality == 'video') videoAvailable = !nextVideo;
      });
      showError(context, e);
    } finally {
      if (mounted) setState(() => modalityBusy = false);
    }
  }

  Future<void> _beat() async {
    if (presence == 'ONLINE') {
      try {
        await context.read<AppController>().api.presenceHeartbeat();
      } catch (_) {}
    }
  }

  Future<void> _toggle() async {
    final isOnlineOrBusy = presence == 'ONLINE' || presence == 'BUSY_IN_CALL' || presence == 'BUSY';
    final next = isOnlineOrBusy ? 'OFFLINE' : 'ONLINE';
    try {
      final result = await context.read<AppController>().api.updatePresence(next);
      if (!mounted) return;
      setState(() {
        presence = '${result['presence'] ?? result['presenceStatus'] ?? next}';
      });
      context.read<AppController>().updatePresence(presence);
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _callback(InstantSessionModel s) async {
    try {
      final callback = await context.read<AppController>().api.callbackSession(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Calling ${s.callerNickname} back…')));
      var current = callback;
      for (var i = 0; i < 40 && mounted; i++) {
        if (const {'ACCEPTED', 'CONNECTED', 'ACTIVE'}.contains(current.status)) {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionScreen(initialSession: current, callerSide: false)));
          await _load(silent: true);
          return;
        }
        if (const {'EXPIRED', 'REJECTED', 'CANCELLED'}.contains(current.status)) {
          throw Exception('Callback was not picked up. You can try again later.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        current = await context.read<AppController>().api.session(current.id);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _formatSessionTime(InstantSessionModel s) {
    final d = DateTime.tryParse(s.connectedAt ?? s.startedAt ?? s.requestedAt ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final timeStr = DateFormat('h:mm a').format(d);
    if (day == today) return 'Today, $timeStr';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $timeStr';
    return '${DateFormat('dd MMM').format(d)}, $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(backgroundColor: bgCream, body: LoadingBody());

    final displayName = '${profile?['displayName'] ?? profile?['fullName'] ?? 'Listener'}';
    final avatarUrl = profile?['avatarUrl']?.toString();
    final targetSeconds = (attendance?['targetSeconds'] as num?)?.toInt() ?? 10800; // 3h = 10800s
    final online = liveOnlineSeconds.clamp(0, 1 << 30).toInt();
    final remaining = (targetSeconds - online).clamp(0, targetSeconds).toInt();
    final percent = targetSeconds <= 0 ? 0.0 : (online / targetSeconds).clamp(0.0, 1.0).toDouble();
    final isOnline = presence == 'ONLINE';
    final isBusy = presence == 'BUSY_IN_CALL' || presence == 'BUSY' || (activeSessionType != null && activeSessionType!.isNotEmpty);
    final ratePerMin = (profile?['ratePerMinute'] as num?)?.toDouble() ?? 39.5;
    final videoRatePerMin = (profile?['videoRatePerMinute'] as num?)?.toDouble() ?? (ratePerMin * 1.5);
    final chatRatePerMin = (profile?['chatRatePerMinute'] as num?)?.toDouble() ?? (ratePerMin * 0.6);
    final netShareAudio = (ratePerMin * 0.50).round();
    final netShareVideo = (videoRatePerMin * 0.50).round();
    final netShareChat = (chatRatePerMin * 0.50).round();

    final completedSessionsCount = sessions.where((s) => s.status == 'COMPLETED' || (s.durationSeconds > 0 && !const {'CANCELLED', 'REJECTED'}.contains(s.status))).length;
    final dbConsultations = (profile?['totalConsultations'] as num?)?.toInt() ?? 0;
    final totalConsultations = dbConsultations > completedSessionsCount ? dbConsultations : (completedSessionsCount > 0 ? completedSessionsCount : (sessions.isNotEmpty ? sessions.length : 0));

    final rawReviews = (profile?['reviewCount'] ?? profile?['ratingCount'] as num?)?.toInt() ?? 0;
    final rawRating = (profile?['ratingAvg'] as num?)?.toDouble() ?? 0.0;
    final hasRatings = rawReviews > 0 && rawRating > 0;
    final ratingCount = rawReviews;
    final ratingAvg = hasRatings ? rawRating : 0.0;
    final ratingDisplay = hasRatings ? '⭐ ${ratingAvg.toStringAsFixed(1)}' : '⭐ New';
    final ratingSub = rawReviews == 0
        ? 'No caller ratings yet'
        : 'Across $ratingCount caller ${ratingCount == 1 ? "rating" : "ratings"}';
    final walletBalance = wallet?.formattedBalance ?? '₹1628.00';
    final totalGifts = sessions.fold<double>(0.0, (acc, s) => acc + s.giftEarnings);

    final missed = sessions
        .where((s) => const {'EXPIRED', 'REJECTED', 'CANCELLED', 'MISSED'}.contains(s.status) && !s.reference.startsWith('CB-') && !dismissedMissed.contains(s.id))
        .toList();

    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryOrange,
          backgroundColor: Colors.white,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 30),
            children: [
              // ==========================================
              // 1. TOP APP BAR (Logo + Earnings Pill + Profile Pill)
              // ==========================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo + Brand Title + Subtitle
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [secondaryOrange, primaryOrange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.4,
                          ),
                          children: [
                            TextSpan(text: 'Hear'),
                            TextSpan(text: 'Me', style: TextStyle(color: primaryOrange)),
                          ],
                        ),
                      ),
                      const Text(
                        'Listen. Support. Earn.',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Earnings Pill
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => widget.onNavigateTab?.call(2), // Navigate to Earnings
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderWarm, width: 0.9),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 16, color: primaryOrange),
                          const SizedBox(width: 5),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Earnings', style: TextStyle(fontSize: 8.5, color: textMuted, fontWeight: FontWeight.w500)),
                              Text(walletBalance, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFFEA580C))),
                            ],
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF9CA3AF)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Profile Pill
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => widget.onNavigateTab?.call(3), // Navigate to Profile
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            RemoteAvatar(
                              url: avatarUrl,
                              radius: 17,
                              fallback: displayName,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName.split(' ').first,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textDark),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 13, color: Color(0xFF9CA3AF)),
                              ],
                            ),
                            Text(
                              isOnline ? 'Online Listener' : isBusy ? 'Busy in Call' : 'Offline',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ==========================================
              // 2. ROW 1: Daily Target Card + Missed Calls Card
              // ==========================================
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Daily 3-Hour Target Card
                  Expanded(
                    flex: 11,
                    child: _DailyTargetCard(
                      onlineSeconds: online,
                      remainingSeconds: remaining,
                      percent: percent,
                      isOnline: isOnline,
                      isBusy: isBusy,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Right: Missed Calls & Callback Card
                  Expanded(
                    flex: 9,
                    child: _MissedCallsCard(
                      missedList: missed,
                      onCallback: _callback,
                    ),
                  ),
                ],
              ),

              // ==========================================
              // 2.5 PEER LISTENERS LIVE STATUS CARD
              // ==========================================
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ListenerPeersScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderWarm, width: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.people_outline_rounded, size: 22, color: Color(0xFF2563EB)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Other Listeners Live Status',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: textDark,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Monitor who is online, offline or busy in calls',
                              style: TextStyle(
                                fontSize: 11,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: softPeach,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Text(
                              'View Live',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: primaryOrange,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 14, color: primaryOrange),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ==========================================
              // 3. PROFILE MINI-BANNER CARD
              // ==========================================
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => widget.onNavigateTab?.call(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderWarm, width: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          RemoteAvatar(
                            url: avatarUrl,
                            radius: 23,
                            fallback: displayName,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: textDark,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8FDF3),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: emeraldOnline.withValues(alpha: 0.3), width: 0.7),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded, size: 10, color: emeraldOnline),
                                      SizedBox(width: 3),
                                      Text(
                                        'VERIFIED PEER',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF047857),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Manage your incoming calls, instant payouts, and consultation ledger.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: textMuted, height: 1.25),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ==========================================
              // 4. AVAILABILITY & MODALITY CONTROLS CARD
              // ==========================================
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderWarm, width: 0.9),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Availability Switch
                    Expanded(
                      flex: 11,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Text(
                                'Availability',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: textDark),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _PresenceSliderSwitch(
                            isOnline: isOnline || isBusy,
                            onToggle: _toggle,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // 3 Modality Buttons (Chat, Voice Call, Video Call)
                    Expanded(
                      flex: 14,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _ModalityButton(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Chat',
                            isActive: chatAvailable,
                            onTap: () => _toggleModality('chat'),
                          ),
                          _ModalityButton(
                            icon: Icons.call_rounded,
                            label: 'Voice Call',
                            isActive: audioAvailable,
                            onTap: () => _toggleModality('audio'),
                          ),
                          _ModalityButton(
                            icon: Icons.videocam_rounded,
                            label: 'Video Call',
                            isActive: videoAvailable,
                            onTap: () => _toggleModality('video'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // ==========================================
              // 5. FINANCIAL & PERFORMANCE METRICS
              // ==========================================
              // Grid Row 1: Available Payout Balance + Lifetime Earnings
              Row(
                children: [
                  // Available Payout Balance
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Available Payout Balance',
                      value: walletBalance,
                      actionLabel: 'Withdraw to UPI',
                      actionIcon: Icons.arrow_downward_rounded,
                      onActionTap: () => widget.onNavigateTab?.call(2),
                      illustration: _RupeeCardIllustration(),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Lifetime Earnings
                  Expanded(
                    child: _MetricCard(
                      icon: Icons.bar_chart_rounded,
                      title: 'Lifetime Earnings',
                      value: walletBalance,
                      illustration: _BarChartIllustration(),
                      onTap: () => widget.onNavigateTab?.call(2),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Grid Row 2: Consultation Rates (Voice, Video & Chat) + Sessions & Rating
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Consultation Rates (Audio, Video, Chat)
                    Expanded(
                      child: _ConsultationRatesCard(
                        audioRate: ratePerMin,
                        videoRate: videoRatePerMin,
                        chatRate: chatRatePerMin,
                        audioNet: netShareAudio,
                        videoNet: netShareVideo,
                        chatNet: netShareChat,
                        onTap: () => widget.onNavigateTab?.call(3),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Sessions & Rating
                    Expanded(
                      child: _SessionsRatingCard(
                        totalConsultations: totalConsultations,
                        completedCount: completedSessionsCount,
                        ratingDisplay: ratingDisplay,
                        ratingSub: ratingSub,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ListenerReviewsScreen()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Gifts & Tips Card (Full Width)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => widget.onNavigateTab?.call(2),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderWarm, width: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: softPeach,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.card_giftcard_rounded, color: primaryOrange, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('Gifts & Tips', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textDark)),
                                SizedBox(width: 3),
                                Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF9CA3AF)),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text('₹${totalGifts.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryOrange)),
                            const Text('0 virtual gifts (Rose, etc.)', style: TextStyle(fontSize: 10.5, color: textMuted)),
                          ],
                        ),
                      ),
                      // 3D Gift box with hearts
                      _GiftBoxIllustration(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ==========================================
              // 6. SUB-NAVIGATION HORIZONTAL RAIL
              // ==========================================
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _SubNavTab(
                      icon: Icons.phone_in_talk_rounded,
                      label: 'Calls & Chats (${sessions.length})',
                      isSelected: selectedSubTab == 0,
                      onTap: () => setState(() => selectedSubTab = 0),
                    ),
                    _SubNavTab(
                      icon: Icons.calendar_today_outlined,
                      label: 'Attendance',
                      isSelected: selectedSubTab == 1,
                      onTap: () => widget.onNavigateTab?.call(1),
                    ),
                    _SubNavTab(
                      icon: Icons.receipt_long_outlined,
                      label: 'Transactions',
                      isSelected: selectedSubTab == 2,
                      onTap: () => widget.onNavigateTab?.call(2),
                    ),
                    _SubNavTab(
                      icon: Icons.bar_chart_rounded,
                      label: 'Earnings',
                      isSelected: selectedSubTab == 3,
                      onTap: () => widget.onNavigateTab?.call(2),
                    ),
                    _SubNavTab(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Gifts',
                      isSelected: selectedSubTab == 4,
                      onTap: () => setState(() => selectedSubTab = 4),
                    ),
                    _SubNavTab(
                      icon: Icons.file_upload_outlined,
                      label: 'UPI',
                      isSelected: selectedSubTab == 5,
                      onTap: () => widget.onNavigateTab?.call(2),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ==========================================
              // 7. CONVERSATIONS LIST OR ILLUSTRATED EMPTY STATE
              // ==========================================
              if (sessions.isEmpty)
                // Illustrated Empty State matching the screenshot!
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderWarm, width: 0.9),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Illustration of female listener working on laptop with headphones & speech bubbles
                      const SizedBox(
                        width: 120,
                        height: 100,
                        child: _ListenerAvatarWorkingIllustration(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No conversations recorded yet',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Keep your availability set to ONLINE. When callers connect for Audio, Video, or Chat, their anonymous profiles, exact timings, and your per-minute earnings will appear here.',
                              style: TextStyle(fontSize: 10.5, color: textMuted, height: 1.3),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: isOnline ? null : _toggle,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  gradient: LinearGradient(
                                    colors: isOnline
                                        ? [emeraldOnline, const Color(0xFF059669)]
                                        : [secondaryOrange, primaryOrange],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isOnline ? emeraldOnline : primaryOrange).withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isOnline ? 'You Are Online' : 'Go Online Now',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Real Live / Completed Sessions Feed
                ...sessions.take(6).map((s) {
                  final earned = s.effectiveListenerEarnings;
                  final isLive = s.isLive;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderWarm, width: 0.8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: softPeach,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            s.type == 'CHAT'
                                ? Icons.chat_bubble_rounded
                                : s.type == 'VIDEO_CALL'
                                    ? Icons.videocam_rounded
                                    : Icons.call_rounded,
                            color: primaryOrange,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(s.callerNickname, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textDark)),
                                  if (isLive) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(color: const Color(0xFFE8FDF3), borderRadius: BorderRadius.circular(4)),
                                      child: const Text('LIVE', style: TextStyle(color: Color(0xFF047857), fontSize: 8.5, fontWeight: FontWeight.w900)),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '${s.type.replaceAll('_', ' ')} • ${_formatSessionTime(s)}${s.billableMinutes > 0 ? ' • ${s.billableMinutes} min' : ''}',
                                style: const TextStyle(fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (earned > 0)
                              Text('+₹${earned.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: emeraldOnline))
                            else if (isLive)
                              Text('₹${s.ratePerMinute.toStringAsFixed(0)}/m', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: primaryOrange))
                            else
                              const Text('₹0.00', style: TextStyle(fontSize: 12, color: textMuted)),
                            if (s.giftEarnings > 0)
                              Text('+₹${s.giftEarnings.toStringAsFixed(0)} 🎁', style: const TextStyle(fontSize: 10, color: Color(0xFFEC4899), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// CUSTOM COMPONENTS
// ==========================================

class _DailyTargetCard extends StatelessWidget {
  final int onlineSeconds;
  final int remainingSeconds;
  final double percent;
  final bool isOnline;
  final bool isBusy;

  const _DailyTargetCard({
    required this.onlineSeconds,
    required this.remainingSeconds,
    required this.percent,
    required this.isOnline,
    required this.isBusy,
  });

  String _hms(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h}h ${m}m ${sec}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1E6D8), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Title + Date + Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.track_changes_rounded, size: 14, color: Color(0xFFF95B3D)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Daily 3-Hour Target',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                    ),
                    Text(
                      'Today (${DateFormat('yyyy-MM-dd').format(DateTime.now())}) • IST',
                      style: const TextStyle(fontSize: 8.5, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF10B981) : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF6B7280),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isOnline ? 'ONLINE' : isBusy ? 'BUSY' : 'OFFLINE',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: isOnline ? const Color(0xFF10B981) : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Center: Circular Progress Ring + Stats
          Row(
            children: [
              // Ring
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: percent,
                      strokeWidth: 5,
                      backgroundColor: const Color(0xFFFFECE5),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF95B3D)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(percent * 100).round()}%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                        ),
                        const Text(
                          'of 3h Goal',
                          style: TextStyle(fontSize: 6.5, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Time stats
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hms(onlineSeconds),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                    ),
                    Text(
                      remainingSeconds > 0 ? 'Remaining ${_hms(remainingSeconds)}' : 'Daily Goal Met! 🎉',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: percent,
                        minHeight: 3.5,
                        backgroundColor: const Color(0xFFFFECE5),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF95B3D)),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 8, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            remainingSeconds > 0 ? '${_hms(remainingSeconds)} left to meet daily target' : 'Target completed',
                            style: const TextStyle(fontSize: 7.5, color: Color(0xFF9CA3AF)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Alert banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A), width: 0.7),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 10, color: Color(0xFFD97706)),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Must maintain 3h online daily, 7 consecutive missed days eligible for admin deactivation.',
                    style: TextStyle(fontSize: 7.5, color: Color(0xFF92400E), height: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissedCallsCard extends StatelessWidget {
  final List<InstantSessionModel> missedList;
  final void Function(InstantSessionModel) onCallback;

  const _MissedCallsCard({
    required this.missedList,
    required this.onCallback,
  });

  String _formatAgo(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Recent';
    final d = DateTime.tryParse(timeStr)?.toLocal();
    if (d == null) return 'Recent';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('dd MMM').format(d);
  }

  void _showMissedCallsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _MissedCallsSheet(
        missedList: missedList,
        onCallback: onCallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = missedList.length;
    final latest = count > 0 ? missedList.first : null;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showMissedCallsSheet(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: count > 0 ? const Color(0xFFFFD5C8) : const Color(0xFFF1E6D8),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Title + Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECE5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_callback_rounded, size: 14, color: Color(0xFFF95B3D)),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Missed Calls &\nCallback',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF111827), height: 1.15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: count > 0 ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count Missed',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: count > 0 ? const Color(0xFFEF4444) : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            if (latest == null) ...[
              // Empty State Illustration
              Center(
                child: SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFECE5).withValues(alpha: 0.6),
                        ),
                      ),
                      const Icon(Icons.phone_forwarded_rounded, size: 24, color: Color(0xFFF95B3D)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'No missed calls right now.\nGreat job!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: Color(0xFF6B7280), height: 1.2),
                ),
              ),
            ] else ...[
              // Latest missed call preview
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECE5),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                    ),
                    child: Center(
                      child: Text(
                        latest.callerNickname.isNotEmpty ? latest.callerNickname.substring(0, 1).toUpperCase() : 'C',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFFF95B3D)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latest.callerNickname.isNotEmpty ? latest.callerNickname : 'Anonymous Caller',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                        ),
                        Text(
                          '${latest.type.toUpperCase().contains('VIDEO') ? '📹 Video' : '📞 Voice'} • ${_formatAgo(latest.requestedAt ?? latest.connectedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Actionable Call Back Button
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onCallback(latest),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone_callback_rounded, color: Colors.white, size: 12),
                      SizedBox(width: 5),
                      Text(
                        'Call Back',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  count > 1 ? '+$count missed • View all ›' : 'Tap to view details ›',
                  style: const TextStyle(fontSize: 8.5, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissedCallsSheet extends StatelessWidget {
  final List<InstantSessionModel> missedList;
  final void Function(InstantSessionModel) onCallback;

  const _MissedCallsSheet({
    required this.missedList,
    required this.onCallback,
  });

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'Recent';
    final d = DateTime.tryParse(timeStr)?.toLocal();
    if (d == null) return 'Recent';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final timeFormatted = DateFormat('h:mm a').format(d);
    if (day == today) return 'Today, $timeFormatted';
    return '${DateFormat('dd MMM').format(d)}, $timeFormatted';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone_callback_rounded, color: Color(0xFFF95B3D), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Missed Calls (${missedList.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Text(
                      'Call back callers who tried to reach you',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF9CA3AF)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF3F4F6)),
          if (missedList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text('No missed calls waiting.', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: missedList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final s = missedList[i];
                  final isVideo = s.type.toUpperCase().contains('VIDEO');
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF5EE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1E6D8)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFECE5),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFCDFD5)),
                          ),
                          child: Center(
                            child: Icon(
                              isVideo ? Icons.videocam_rounded : Icons.phone_missed_rounded,
                              color: const Color(0xFFF95B3D),
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.callerNickname.isNotEmpty ? s.callerNickname : 'Anonymous Caller',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF111827)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${isVideo ? "Video Call" : "Audio Call"} • ${_formatTime(s.requestedAt ?? s.connectedAt)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF95B3D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.phone_forwarded_rounded, size: 14),
                          label: const Text('Call Back', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            onCallback(s);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsultationRatesCard extends StatelessWidget {
  final double audioRate;
  final double videoRate;
  final double chatRate;
  final int audioNet;
  final int videoNet;
  final int chatNet;
  final VoidCallback? onTap;

  const _ConsultationRatesCard({
    required this.audioRate,
    required this.videoRate,
    required this.chatRate,
    required this.audioNet,
    required this.videoNet,
    required this.chatNet,
    this.onTap,
  });

  Widget _rateRow(IconData icon, String label, double rate, int net, Color iconColor) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${rate.toStringAsFixed(1)}/m',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
            ),
            Text(
              '₹$net net',
              style: const TextStyle(fontSize: 8.5, color: Color(0xFF10B981), fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1E6D8), width: 0.9),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              bottom: 2,
              child: _WaveformIllustration(),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFECE5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.price_change_outlined, size: 14, color: Color(0xFFF95B3D)),
                    ),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text(
                        'Call & Chat Rates',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF9CA3AF)),
                  ],
                ),
                const SizedBox(height: 8),
                _rateRow(Icons.call_rounded, 'Voice', audioRate, audioNet, const Color(0xFFF95B3D)),
                const SizedBox(height: 5),
                _rateRow(Icons.videocam_rounded, 'Video', videoRate, videoNet, const Color(0xFF8B5CF6)),
                const SizedBox(height: 5),
                _rateRow(Icons.chat_bubble_rounded, 'Chat', chatRate, chatNet, const Color(0xFF2563EB)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF5EE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 9, color: Color(0xFF6B7280)),
                      SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          '50% net share to wallet',
                          style: TextStyle(fontSize: 8, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsRatingCard extends StatelessWidget {
  final int totalConsultations;
  final int completedCount;
  final String ratingDisplay;
  final String ratingSub;
  final VoidCallback? onTap;

  const _SessionsRatingCard({
    required this.totalConsultations,
    required this.completedCount,
    required this.ratingDisplay,
    required this.ratingSub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1E6D8), width: 0.9),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECE5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF95B3D)),
                ),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    'Sessions & Rating',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF1F2937)),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF9CA3AF)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$totalConsultations ${totalConsultations == 1 ? "call" : "calls"}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF95B3D),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ratingDisplay,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              ratingSub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF6B7280), height: 1.2),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5EE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.rate_review_outlined, size: 9, color: Color(0xFFF95B3D)),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'View all caller reviews ›',
                      style: TextStyle(fontSize: 8, color: Color(0xFFF95B3D), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceSliderSwitch extends StatelessWidget {
  final bool isOnline;
  final VoidCallback onToggle;

  const _PresenceSliderSwitch({
    required this.isOnline,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        height: 36,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
        ),
        child: Row(
          children: [
            // Left Half: Offline
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: !isOnline ? const Color(0xFF6B7280) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: !isOnline ? FontWeight.w800 : FontWeight.w600,
                      color: !isOnline ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ),

            // Right Half: Online (with white circle knob)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: isOnline
                      ? const LinearGradient(
                          colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isOnline)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isOnline ? FontWeight.w800 : FontWeight.w600,
                          color: isOnline ? Colors.white : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalityButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModalityButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFFECE5) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? const Color(0xFFF95B3D).withValues(alpha: 0.4) : const Color(0xFFE5E7EB),
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isActive ? const Color(0xFFF95B3D) : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? const Color(0xFF111827) : const Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? valueUnit;
  final String? ratingValue;
  final String? subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onTap;
  final Widget? illustration;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    this.valueUnit,
    this.ratingValue,
    this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onActionTap,
    this.onTap,
    this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1E6D8), width: 0.9),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD6C7B8).withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (illustration != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: illustration!,
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFECE5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 14, color: const Color(0xFFF95B3D)),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFF9CA3AF)),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF95B3D),
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (valueUnit != null)
                      Text(
                        valueUnit!,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                      ),
                    if (ratingValue != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        ratingValue!,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B)),
                      ),
                    ],
                  ],
                ),

                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 9.5, color: Color(0xFF6B7280), height: 1.2),
                  ),
                ],

                if (actionLabel != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: onActionTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF95B3D).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (actionIcon != null) ...[
                            Icon(actionIcon!, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            actionLabel!,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubNavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SubNavTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: isSelected
                ? const Border(bottom: BorderSide(color: Color(0xFFF95B3D), width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? const Color(0xFFF95B3D) : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Vector/Canvas Graphic Illustrations
class _RupeeCardIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Transform.rotate(
        angle: 0.15,
        child: Container(
          width: 48,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFFFECE5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF95B3D).withValues(alpha: 0.3)),
          ),
          child: const Center(
            child: Text('₹', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFF95B3D))),
          ),
        ),
      ),
    );
  }
}

class _BarChartIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(width: 6, height: 14, color: const Color(0xFFF95B3D), margin: const EdgeInsets.only(right: 3)),
          Container(width: 6, height: 22, color: const Color(0xFFF95B3D), margin: const EdgeInsets.only(right: 3)),
          Container(width: 6, height: 32, color: const Color(0xFFF95B3D)),
        ],
      ),
    );
  }
}

class _WaveformIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.35,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(width: 3, height: 10, color: const Color(0xFFF95B3D), margin: const EdgeInsets.only(right: 2)),
          Container(width: 3, height: 18, color: const Color(0xFFF95B3D), margin: const EdgeInsets.only(right: 2)),
          Container(width: 3, height: 12, color: const Color(0xFFF95B3D), margin: const EdgeInsets.only(right: 2)),
          Container(width: 3, height: 24, color: const Color(0xFFF95B3D)),
        ],
      ),
    );
  }
}

class _GiftBoxIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.4)),
            ),
            child: const Center(
              child: Icon(Icons.card_giftcard_rounded, color: Color(0xFFF43F5E), size: 20),
            ),
          ),
          Positioned(
            top: 0,
            right: 4,
            child: Text('❤️', style: TextStyle(fontSize: 10)),
          ),
          Positioned(
            bottom: 2,
            left: 2,
            child: Text('✨', style: TextStyle(fontSize: 8)),
          ),
        ],
      ),
    );
  }
}

class _ListenerAvatarWorkingIllustration extends StatelessWidget {
  const _ListenerAvatarWorkingIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Warm peach circular glow
        Positioned(
          left: 10,
          bottom: 10,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFECE5).withValues(alpha: 0.8),
            ),
          ),
        ),
        // Listener Avatar with headphones and laptop
        Positioned(
          left: 15,
          bottom: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(0xFFFED7AA),
                    child: Icon(Icons.face_3_rounded, size: 26, color: Color(0xFF9A3412)),
                  ),
                  Positioned(
                    top: 0,
                    child: Container(
                      width: 44,
                      height: 18,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF1F2937), width: 2),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // Laptop
              Container(
                width: 46,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF4B5563),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Icon(Icons.apple, size: 10, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        // Speech Bubble
        Positioned(
          top: 8,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF1E6D8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('💬', style: TextStyle(fontSize: 10)),
                SizedBox(width: 2),
                Text('•••', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFF95B3D))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
