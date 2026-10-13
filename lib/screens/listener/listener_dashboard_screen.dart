import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

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
      ActiveCallManager.instance.startCall(callback, callerSide: false);
      await _load(silent: true);
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

    final app = context.watch<AppController>();
    final user = app.user;
    final listenerName = (user?.fullName.trim().isNotEmpty == true
            ? user!.fullName.trim()
            : (profile?['name'] ?? profile?['displayName'] ?? profile?['fullName'] ?? 'Listener'))
        .toString();
    final avatarUrl = profile?['avatarUrl']?.toString();
    final targetSeconds = (attendance?['targetSeconds'] as num?)?.toInt() ?? 10800; // 3h = 10800s
    final online = liveOnlineSeconds.clamp(0, 1 << 30).toInt();
    final remaining = (targetSeconds - online).clamp(0, targetSeconds).toInt();
    final percent = targetSeconds <= 0 ? 0.0 : (online / targetSeconds).clamp(0.0, 1.0).toDouble();
    final isOnline = presence == 'ONLINE';
    final isBusy = presence == 'BUSY_IN_CALL' || presence == 'BUSY' || (activeSessionType != null && activeSessionType!.isNotEmpty);
    final rawReviews = (profile?['reviewCount'] ?? profile?['ratingCount'] as num?)?.toInt() ?? 0;
    final rawRating = (profile?['ratingAvg'] as num?)?.toDouble() ?? 0.0;
    final hasRatings = rawReviews > 0 && rawRating > 0;
    final ratingAvg = hasRatings ? rawRating : 0.0;
    final ratingDisplay = hasRatings ? '⭐ ${ratingAvg.toStringAsFixed(1)}' : '⭐ New';
    final walletBalance = wallet?.formattedBalance ?? '₹0.00';
    final missed = sessions
        .where((s) => const {'EXPIRED', 'REJECTED', 'CANCELLED', 'MISSED'}.contains(s.status) && !s.reference.startsWith('CB-') && !dismissedMissed.contains(s.id))
        .toList();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todaySessions = sessions.where((s) {
      final dt = DateTime.tryParse(s.connectedAt ?? s.startedAt ?? s.requestedAt ?? '')?.toLocal();
      if (dt == null) return false;
      return dt.year == today.year && dt.month == today.month && dt.day == today.day;
    }).toList();
    final todayEarnings = todaySessions.fold<double>(0.0, (acc, s) => acc + s.effectiveListenerEarnings);
    final todayCompleted = todaySessions.where((s) => s.isCompleted || (s.durationSeconds > 0 && !const {'CANCELLED', 'REJECTED'}.contains(s.status))).length;

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
                  // FeelAgain Splash Logo
                  Image.asset(
                    'assets/images/feelagain-splash.png',
                    height: 27,
                    fit: BoxFit.contain,
                  ),

                  const Spacer(),

                  // Earnings Pill
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
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

                  // Profile Pill with Listener Name in place of 'Online Listener'
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onNavigateTab?.call(3), // Navigate to Profile
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
                          Stack(
                            children: [
                              RemoteAvatar(
                                url: avatarUrl,
                                radius: 15,
                                fallback: listenerName,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 105),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Listener',
                                      style: TextStyle(fontSize: 8.5, color: textMuted, fontWeight: FontWeight.w500),
                                    ),
                                    SizedBox(width: 1),
                                    Icon(Icons.chevron_right_rounded, size: 12, color: Color(0xFF9CA3AF)),
                                  ],
                                ),
                                Text(
                                  listenerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ==========================================
              // 2. HERO AVAILABILITY & CHANNEL CONTROLS
              // ==========================================
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: borderWarm, width: 0.9),
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
                    // Top Row: Availability title & live status on Left, Presence Slider Switch on Right
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : const Color(0xFF9CA3AF),
                                shape: BoxShape.circle,
                                boxShadow: isOnline
                                    ? [
                                        BoxShadow(
                                          color: emeraldOnline.withValues(alpha: 0.5),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Availability',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark),
                                ),
                                Text(
                                  isOnline
                                      ? 'Accepting calls'
                                      : isBusy
                                          ? 'Currently in call'
                                          : 'Offline · Turn on to receive calls',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: isOnline ? emeraldOnline : isBusy ? const Color(0xFFF59E0B) : textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 135,
                          child: _PresenceSliderSwitch(
                            isOnline: isOnline || isBusy,
                            onToggle: _toggle,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Bottom Row: 3 Beautiful Toggle Buttons for Chat, Voice Call, Video Call
                    Row(
                      children: [
                        Expanded(
                          child: _ModalityToggleButton(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Chat',
                            isActive: chatAvailable,
                            isBusy: modalityBusy,
                            onToggle: () => _toggleModality('chat'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModalityToggleButton(
                            icon: Icons.call_rounded,
                            label: 'Voice Call',
                            isActive: audioAvailable,
                            isBusy: modalityBusy,
                            onToggle: () => _toggleModality('audio'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ModalityToggleButton(
                            icon: Icons.videocam_rounded,
                            label: 'Video Call',
                            isActive: videoAvailable,
                            isBusy: modalityBusy,
                            onToggle: () => _toggleModality('video'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ==========================================
              // 3. DAILY 3-HOUR SHIFT & MISSED CALLBACK
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

              const SizedBox(height: 12),

              // ==========================================
              // 4. TODAY'S SNAPSHOT CARD
              // ==========================================
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderWarm, width: 0.9),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD6C7B8).withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Today's Overview",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: textDark,
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onNavigateTab?.call(2),
                          borderRadius: BorderRadius.circular(8),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View in Earnings',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Stat 1: Today's Earnings
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Today Earned', style: TextStyle(fontSize: 10.5, color: textMuted, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(
                                '₹${todayEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark),
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 28, color: borderWarm),
                        // Stat 2: Completed Calls
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Calls Today', style: TextStyle(fontSize: 10.5, color: textMuted, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(
                                  '$todayCompleted',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: textDark),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(width: 1, height: 28, color: borderWarm),
                        // Stat 3: Caller Rating
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Rating', style: TextStyle(fontSize: 10.5, color: textMuted, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(
                                  ratingDisplay,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: primaryOrange),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ==========================================
              // 5. PENDING MISSED CALLS QUEUE OR PEACEFUL STATE
              // ==========================================
              if (missed.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Missed Callers',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${missed.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => widget.onNavigateTab?.call(1),
                      child: const Text(
                        'View All in Attendance ›',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primaryOrange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...missed.take(3).map((s) {
                  final callerNick = s.callerNickname.isNotEmpty ? s.callerNickname : 'Anonymous Caller';
                  final isVideo = s.type.toUpperCase().contains('VIDEO');
                  final isChat = s.type.toUpperCase().contains('CHAT');
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFECE5),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isChat ? Icons.chat_bubble_rounded : (isVideo ? Icons.videocam_rounded : Icons.call_missed_rounded),
                              color: primaryOrange,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                callerNick,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: textDark),
                              ),
                              Text(
                                '${s.type.replaceAll('_', ' ')} • ${_formatSessionTime(s)}',
                                style: const TextStyle(fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                        // Quick Callback action
                        InkWell(
                          onTap: () => _callback(s),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryOrange,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryOrange.withValues(alpha: 0.25),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isChat ? Icons.chat_bubble_rounded : (isVideo ? Icons.videocam_rounded : Icons.phone_callback_rounded),
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isChat ? 'Chat' : (isVideo ? 'Video' : 'Call Back'),
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
              ] else ...[
                // Peaceful All-Caught-Up State
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderWarm),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8FDF3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All caught up!',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textDark),
                            ),
                            Text(
                              'No pending missed calls. Stay online to receive caller requests.',
                              style: TextStyle(fontSize: 10.5, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ==========================================
              // 6. QUICK NAVIGATION TILES
              // ==========================================
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => widget.onNavigateTab?.call(1),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9F4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFDE8DF)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.calendar_month_rounded, color: primaryOrange, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Attendance Log',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textDark),
                                  ),
                                  Text('30-day shift & sessions', style: TextStyle(fontSize: 9.5, color: textMuted)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 16, color: primaryOrange),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => widget.onNavigateTab?.call(4),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderWarm),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: Color(0xFF6366F1), size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rates & Settings',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textDark),
                                  ),
                                  Text('In More menu', style: TextStyle(fontSize: 9.5, color: textMuted)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF6366F1)),
                          ],
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
    final navContext = getSafeNavigatorContext(context);
    showModalBottomSheet<void>(
      context: navContext,
      useRootNavigator: true,
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

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showMissedCallsSheet(context),
              child: Row(
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
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showMissedCallsSheet(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View history',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 8,
                        color: Color(0xFF9CA3AF),
                      ),
                    ],
                  ),
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
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
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showMissedCallsSheet(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6F3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFD5C8), width: 0.8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        count > 1 ? '+$count missed • View all' : 'Tap to view details',
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFF95B3D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 9,
                        color: Color(0xFFF95B3D),
                      ),
                    ],
                  ),
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
    if (timeStr == null || timeStr.trim().isEmpty) return 'Recent';
    try {
      final d = DateTime.tryParse(timeStr)?.toLocal();
      if (d == null) return 'Recent';
      final now = DateTime.now();
      final diff = now.difference(d);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      final today = DateTime(now.year, now.month, now.day);
      final day = DateTime(d.year, d.month, d.day);
      final timeFormatted = DateFormat('h:mm a').format(d);
      if (day == today) return 'Today, $timeFormatted';
      return '${DateFormat('dd MMM').format(d)}, $timeFormatted';
    } catch (_) {
      return 'Recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = missedList.isEmpty
        ? 260.0
        : (screenHeight * 0.78).clamp(360.0, 750.0);

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
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
                        padding: const EdgeInsets.all(8),
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
                  const SizedBox(height: 8),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                ],
              ),
            ),
            if (missedList.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No missed calls waiting.', style: TextStyle(color: Color(0xFF9CA3AF))),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  itemCount: missedList.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    try {
                      final s = missedList[i];
                      final isVideo = s.type.toUpperCase().contains('VIDEO');
                      final name = s.callerNickname.trim().isNotEmpty ? s.callerNickname.trim() : 'Anonymous Caller';
                      final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'C';

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
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFECE5),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFCDFD5), width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  initial,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Color(0xFFF95B3D),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isVideo ? const Color(0xFFEDE9FE) : const Color(0xFFFFECE5),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isVideo ? Icons.videocam_rounded : Icons.phone_callback_rounded,
                                              size: 10,
                                              color: isVideo ? const Color(0xFF7C3AED) : const Color(0xFFF95B3D),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              isVideo ? 'Video' : 'Voice',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: isVideo ? const Color(0xFF7C3AED) : const Color(0xFFF95B3D),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _formatTime(s.requestedAt ?? s.connectedAt),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onCallback(s);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1.5),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.phone_forwarded_rounded, color: Colors.white, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'Call Back',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } catch (_) {
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


void showConsultationRatesSheet({
  required BuildContext context,
  required double audioRate,
  required double videoRate,
  required double chatRate,
  required int audioNet,
  required int videoNet,
  required int chatNet,
  VoidCallback? onEditRates,
}) {
  final navContext = getSafeNavigatorContext(context);
  showModalBottomSheet<void>(
    context: navContext,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ConsultationRatesSheet(
      audioRate: audioRate,
      videoRate: videoRate,
      chatRate: chatRate,
      audioNet: audioNet,
      videoNet: videoNet,
      chatNet: chatNet,
      onEditRates: onEditRates ?? () => Navigator.of(ctx).pop(),
    ),
  );
}

class ConsultationRatesSheet extends StatelessWidget {
  final double audioRate;
  final double videoRate;
  final double chatRate;
  final int audioNet;
  final int videoNet;
  final int chatNet;
  final VoidCallback onEditRates;

  const ConsultationRatesSheet({
    super.key,
    required this.audioRate,
    required this.videoRate,
    required this.chatRate,
    required this.audioNet,
    required this.videoNet,
    required this.chatNet,
    required this.onEditRates,
  });

  Widget _rateItem({
    required IconData icon,
    required String title,
    required String description,
    required double grossRate,
    required int netShare,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF5EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1E6D8)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${grossRate.toStringAsFixed(1)}/min',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FDF3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '₹$netShare net (50%)',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        top: false,
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
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFECE5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.price_change_outlined, color: Color(0xFFF95B3D), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Call & Chat Rates',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      Text(
                        'Your consultation pricing and 50% net earnings share',
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
            const SizedBox(height: 14),
            _rateItem(
              icon: Icons.call_rounded,
              title: 'Voice Call',
              description: 'Standard anonymous audio consultation',
              grossRate: audioRate,
              netShare: audioNet,
              color: const Color(0xFFF95B3D),
            ),
            const SizedBox(height: 10),
            _rateItem(
              icon: Icons.videocam_rounded,
              title: 'Video Call',
              description: 'Face-to-face video consultation',
              grossRate: videoRate,
              netShare: videoNet,
              color: const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 10),
            _rateItem(
              icon: Icons.chat_bubble_rounded,
              title: 'Text Chat',
              description: 'Real-time 1-on-1 private messaging',
              grossRate: chatRate,
              netShare: chatNet,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF5EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1E6D8)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Color(0xFFF95B3D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '50% of the gross caller fee is automatically credited directly to your Available Payout Balance upon session completion.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF4B5563), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onEditRates,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Edit Rates in Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF95B3D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
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

class _ModalityToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isBusy;
  final VoidCallback onToggle;

  const _ModalityToggleButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isBusy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const primaryOrange = Color(0xFFF95B3D);
    const textDark = Color(0xFF111827);
    const textMuted = Color(0xFF6B7280);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: isBusy ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFFFF6F3) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? primaryOrange.withValues(alpha: 0.45) : const Color(0xFFE5E7EB),
            width: isActive ? 1.2 : 0.9,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row with Icon and Mini Toggle Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFFFECE5) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: isActive ? primaryOrange : const Color(0xFF9CA3AF),
                  ),
                ),
                // Smooth Animated iOS-style Toggle Switch
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32,
                  height: 18,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isActive ? primaryOrange : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: isActive ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isActive ? textDark : textMuted,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isActive ? primaryOrange : const Color(0xFF9CA3AF),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3.5),
                Text(
                  isActive ? 'Active' : 'Muted',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: isActive ? primaryOrange : const Color(0xFF9CA3AF),
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

