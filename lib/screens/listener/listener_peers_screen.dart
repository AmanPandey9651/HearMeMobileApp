import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

class ListenerPeersScreen extends StatefulWidget {
  const ListenerPeersScreen({super.key});

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  State<ListenerPeersScreen> createState() => _ListenerPeersScreenState();
}

class _ListenerPeersScreenState extends State<ListenerPeersScreen> {
  List<ListenerCardModel> _listeners = [];
  bool _loading = true;
  String _filter = 'ALL'; // ALL, ONLINE, BUSY, BUSY_AUDIO, BUSY_VIDEO, BUSY_CHAT, OFFLINE
  String _search = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load(isInitial: true);
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(isInitial: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool isInitial = false}) async {
    if (isInitial && mounted) setState(() => _loading = true);
    try {
      final list = await context.read<AppController>().api.allListeners();
      if (mounted) {
        setState(() {
          _listeners = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<ListenerCardModel> get _filtered {
    return _listeners.where((l) {
      // 1. Presence Filter
      if (_filter == 'ONLINE' && !l.isOnline) return false;
      if (_filter == 'BUSY' && !l.isBusy) return false;
      if (_filter == 'OFFLINE' && !l.isOffline) return false;
      if (_filter == 'BUSY_AUDIO' && !l.isBusyAudio) return false;
      if (_filter == 'BUSY_VIDEO' && !l.isBusyVideo) return false;
      if (_filter == 'BUSY_CHAT' && !l.isBusyChat) return false;

      // 2. Search
      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        final nameMatch = l.displayName.toLowerCase().contains(q);
        final titleMatch = l.professionalTitle.toLowerCase().contains(q);
        final catMatch = l.categories.any((c) => c.toLowerCase().contains(q));
        final langMatch = l.languages.any((lang) => lang.toLowerCase().contains(q));
        if (!nameMatch && !titleMatch && !catMatch && !langMatch) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AppController>().user?.id;

    final totalCount = _listeners.length;
    final onlineCount = _listeners.where((l) => l.isOnline).length;
    final busyCount = _listeners.where((l) => l.isBusy).length;
    final busyAudioCount = _listeners.where((l) => l.isBusyAudio).length;
    final busyVideoCount = _listeners.where((l) => l.isBusyVideo).length;
    final busyChatCount = _listeners.where((l) => l.isBusyChat).length;
    final offlineCount = _listeners.where((l) => l.isOffline).length;

    final items = _filtered;

    return Scaffold(
      backgroundColor: ListenerPeersScreen.bgCream,
      body: Stack(
        children: [
          // Top-right warm peach ambient glow orb
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFFFFD8C7),
                    Color(0x00FAF5EE),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              color: ListenerPeersScreen.primaryOrange,
              backgroundColor: Colors.white,
              onRefresh: () => _load(isInitial: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
                children: [
                  // App Bar / Top Navigation
                  Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.maybePop(context),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ListenerPeersScreen.borderWarm),
                          ),
                          child: const Icon(Icons.arrow_back_rounded, size: 20, color: ListenerPeersScreen.textDark),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Other Listeners',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: ListenerPeersScreen.textDark,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Live presence & active consultation monitor',
                              style: TextStyle(
                                fontSize: 12,
                                color: ListenerPeersScreen.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _load(isInitial: false),
                        icon: const Icon(Icons.refresh_rounded, color: ListenerPeersScreen.primaryOrange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 3 Top Metric Cards (Matches Sessions / Earnings stat card layout)
                  Row(
                    children: [
                      // Online Card (Primary Gradient)
                      Expanded(
                        child: _StatCard(
                          title: 'Online Now',
                          value: '$onlineCount',
                          subtitle: 'Available',
                          icon: Icons.wifi_tethering_rounded,
                          isGradient: true,
                          isSelected: _filter == 'ONLINE',
                          onTap: () => setState(() => _filter = _filter == 'ONLINE' ? 'ALL' : 'ONLINE'),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Busy in Calls Card
                      Expanded(
                        child: _StatCard(
                          title: 'Busy in Calls',
                          value: '$busyCount',
                          subtitle: '$busyAudioCount voice • $busyVideoCount vid',
                          icon: Icons.phone_in_talk_rounded,
                          iconColor: const Color(0xFFEF4444),
                          isSelected: _filter == 'BUSY',
                          onTap: () => setState(() => _filter = _filter == 'BUSY' ? 'ALL' : 'BUSY'),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Offline Card
                      Expanded(
                        child: _StatCard(
                          title: 'Offline',
                          value: '$offlineCount',
                          subtitle: 'Total: $totalCount',
                          icon: Icons.access_time_rounded,
                          iconColor: const Color(0xFF6B7280),
                          isSelected: _filter == 'OFFLINE',
                          onTap: () => setState(() => _filter = _filter == 'OFFLINE' ? 'ALL' : 'OFFLINE'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Horizontal Filter Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterPill(
                          label: 'All Listeners',
                          count: totalCount,
                          active: _filter == 'ALL',
                          onTap: () => setState(() => _filter = 'ALL'),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: '🟢 Online',
                          count: onlineCount,
                          active: _filter == 'ONLINE',
                          onTap: () => setState(() => _filter = 'ONLINE'),
                        ),
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: '🔴 Busy (All)',
                          count: busyCount,
                          active: _filter == 'BUSY',
                          onTap: () => setState(() => _filter = 'BUSY'),
                        ),
                        if (busyAudioCount > 0) ...[
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: '📞 Voice Call',
                            count: busyAudioCount,
                            active: _filter == 'BUSY_AUDIO',
                            onTap: () => setState(() => _filter = 'BUSY_AUDIO'),
                          ),
                        ],
                        if (busyVideoCount > 0) ...[
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: '📹 Video Call',
                            count: busyVideoCount,
                            active: _filter == 'BUSY_VIDEO',
                            onTap: () => setState(() => _filter = 'BUSY_VIDEO'),
                          ),
                        ],
                        if (busyChatCount > 0) ...[
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: '💬 Chat Call',
                            count: busyChatCount,
                            active: _filter == 'BUSY_CHAT',
                            onTap: () => setState(() => _filter = 'BUSY_CHAT'),
                          ),
                        ],
                        const SizedBox(width: 8),
                        _FilterPill(
                          label: '⚪ Offline',
                          count: offlineCount,
                          active: _filter == 'OFFLINE',
                          onTap: () => setState(() => _filter = 'OFFLINE'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Search Bar
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ListenerPeersScreen.borderWarm),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20, color: ListenerPeersScreen.primaryOrange),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v),
                            style: const TextStyle(fontSize: 13.5, color: ListenerPeersScreen.textDark),
                            decoration: const InputDecoration(
                              hintText: 'Search by listener name, topic or role...',
                              hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_search.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _search = ''),
                            child: const Icon(Icons.close_rounded, size: 18, color: ListenerPeersScreen.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // List of Listeners
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: ListenerPeersScreen.primaryOrange),
                      ),
                    )
                  else if (items.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: ListenerPeersScreen.borderWarm),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: ListenerPeersScreen.softPeach,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.people_outline_rounded, size: 36, color: ListenerPeersScreen.primaryOrange),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No listeners match this filter',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ListenerPeersScreen.textDark),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Try selecting another status tab or clearing your search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: ListenerPeersScreen.textMuted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...items.map((l) {
                      final isMe = currentUserId != null && l.userId == currentUserId;
                      return _PeerListenerCard(listener: l, isMe: isMe);
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final bool isGradient;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.iconColor,
    this.isGradient = false,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isGradient) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
            boxShadow: const [
              BoxShadow(
                color: Color(0x35F95B3D),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 14, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? ListenerPeersScreen.primaryOrange : ListenerPeersScreen.borderWarm,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ListenerPeersScreen.textMuted),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: (iconColor ?? ListenerPeersScreen.primaryOrange).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 14, color: iconColor ?? ListenerPeersScreen.primaryOrange),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: ListenerPeersScreen.textDark),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: ListenerPeersScreen.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? ListenerPeersScreen.primaryOrange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? ListenerPeersScreen.primaryOrange : ListenerPeersScreen.borderWarm,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : ListenerPeersScreen.textDark,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: active ? Colors.white.withValues(alpha: 0.25) : ListenerPeersScreen.softPeach,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : ListenerPeersScreen.primaryOrange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerListenerCard extends StatelessWidget {
  final ListenerCardModel listener;
  final bool isMe;

  const _PeerListenerCard({
    required this.listener,
    this.isMe = false,
  });

  static String formatLastSeen(String? lastSeenAt) {
    if (lastSeenAt == null || lastSeenAt.trim().isEmpty) {
      return 'Disconnected';
    }
    final dt = DateTime.tryParse(lastSeenAt.trim())?.toLocal();
    if (dt == null) return 'Offline';

    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60 && !diff.isNegative) {
      return 'Active just now';
    }

    if (diff.inMinutes < 60 && !diff.isNegative) {
      return 'Active ${diff.inMinutes}m ago';
    }

    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;

    final timeString = DateFormat('h:mm a').format(dt);

    if (isToday) {
      return 'Last seen today, $timeString';
    }

    if (isYesterday) {
      return 'Last seen yesterday, $timeString';
    }

    if (dt.year == now.year) {
      final dateString = DateFormat('d MMM').format(dt);
      return 'Last seen $dateString, $timeString';
    }

    final fullDate = DateFormat('d MMM yyyy, h:mm a').format(dt);
    return 'Last seen $fullDate';
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = listener.isOnline;
    final isBusy = listener.isBusy;
    final isVideo = listener.isBusyVideo;
    final isChat = listener.isBusyChat;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isBusy
              ? const Color(0xFFFCA5A5)
              : isOnline
                  ? const Color(0xFF86EFAC)
                  : ListenerPeersScreen.borderWarm,
          width: isBusy || isOnline ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isBusy
                ? const Color(0x15EF4444)
                : isOnline
                    ? const Color(0x1510B981)
                    : const Color(0x06000000),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Avatar, Name, Title, and (You) badge
          Row(
            children: [
              // Avatar with live presence ring & beacon
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isBusy
                            ? const Color(0xFFEF4444)
                            : isOnline
                                ? const Color(0xFF10B981)
                                : const Color(0xFF9CA3AF),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: buildAvatarImage(
                        listener.avatarUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            (listener.displayName.isNotEmpty ? listener.displayName[0] : 'L').toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: ListenerPeersScreen.primaryOrange),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isBusy
                            ? const Color(0xFFEF4444)
                            : isOnline
                                ? const Color(0xFF10B981)
                                : const Color(0xFF9CA3AF),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Name & Profession
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            listener.displayName,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: ListenerPeersScreen.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'YOU',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      listener.professionalTitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: ListenerPeersScreen.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          listener.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ListenerPeersScreen.textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${listener.totalConsultations} sessions',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ListenerPeersScreen.textMuted,
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

          // SPECIFIC STATUS BOX: Exactly answering user request ("if busy then in which busy what is status")
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isBusy
                  ? const Color(0xFFFEF2F2)
                  : isOnline
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isBusy
                    ? const Color(0xFFFECACA)
                    : isOnline
                        ? const Color(0xFFA7F3D0)
                        : ListenerPeersScreen.borderWarm,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBusy) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isVideo
                                ? Icons.videocam_rounded
                                : isChat
                                    ? Icons.chat_bubble_rounded
                                    : Icons.phone_in_talk_rounded,
                            size: 16,
                            color: const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            listener.busyLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'BUSY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    listener.busyDescription ??
                        (isVideo
                            ? 'Currently in live video call consultation'
                            : isChat
                                ? 'Currently in live chat exchange'
                                : 'Currently on active phone consultation'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else if (isOnline) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.wifi_tethering_rounded, size: 16, color: Color(0xFF10B981)),
                          SizedBox(width: 6),
                          Text(
                            'Online & Ready',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'READY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Accepting: ${[
                      if (listener.audioAvailable) 'Audio',
                      if (listener.videoAvailable) 'Video',
                      if (listener.chatAvailable) 'Chat',
                    ].join(' • ')}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF065F46),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF6B7280)),
                          SizedBox(width: 6),
                          Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                      Flexible(
                        child: Text(
                          formatLastSeen(listener.lastSeenAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Rates Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rates: Audio ₹${listener.audioRate.toStringAsFixed(0)} • Video ₹${listener.videoRate.toStringAsFixed(0)} • Chat ₹${listener.chatRate.toStringAsFixed(0)}/m',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ListenerPeersScreen.textMuted,
                ),
              ),
            ],
          ),

          // Category Chips
          if (listener.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: listener.categories.take(3).map((cat) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cat,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF4B5563), fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
