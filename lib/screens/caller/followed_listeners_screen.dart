import '../../services/call_launcher.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import 'listener_detail_screen.dart';

class FollowedListenersScreen extends StatefulWidget {
  const FollowedListenersScreen({super.key});

  @override
  State<FollowedListenersScreen> createState() => _FollowedListenersScreenState();
}

class _FollowedListenersScreenState extends State<FollowedListenersScreen> {
  List<ListenerCardModel> _items = [];
  bool _loading = true;
  String _searchQuery = '';
  String _selectedFilter = 'ALL'; // ALL, ONLINE, VOICE, VIDEO, CHAT
  final Set<String> _nudgedIds = <String>{};
  final Set<String> _unfollowingIds = <String>{};

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color emeraldOnline = Color(0xFF10B981);
  static const Color amberBusy = Color(0xFFF59E0B);
  static const Color purpleVideo = Color(0xFF8B5CF6);
  static const Color blueChat = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final api = context.read<AppController>().api;
      final results = await Future.wait<dynamic>([
        api.followedListeners(),
        api.allListeners(),
      ]);
      final followed = List<dynamic>.from(results[0] as List);
      final all = List<ListenerCardModel>.from(results[1] as List<ListenerCardModel>);
      final ids = followed
          .whereType<Map>()
          .map((e) => e['listenerId']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();

      if (mounted) {
        setState(() {
          _items = all.where((e) => ids.contains(e.id)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        if (!silent) showError(context, e);
      }
    }
  }

  Future<void> _unfollow(ListenerCardModel listener) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 16),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.heart_broken_rounded, color: Color(0xFFDC2626), size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                'Remove ${listener.displayName}?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'You will no longer see them in your favourites or receive alerts when they come online.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: textMuted, height: 1.3),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(color: borderWarm),
                      ),
                      child: const Text('Keep Favourite', style: TextStyle(fontWeight: FontWeight.w700, color: textDark)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _unfollowingIds.add(listener.id));
    try {
      final api = context.read<AppController>().api;
      await api.unfollow(listener.id);
      if (mounted) {
        setState(() {
          _items.removeWhere((e) => e.id == listener.id);
          _unfollowingIds.remove(listener.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${listener.displayName} removed from favourites'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _unfollowingIds.remove(listener.id));
        showError(context, e);
      }
    }
  }

  Future<void> _handleNudge(ListenerCardModel listener) async {
    if (_nudgedIds.contains(listener.id)) return;
    try {
      final api = context.read<AppController>().api;
      final result = await api.nudge(listener.id);
      if (mounted) {
        setState(() => _nudgedIds.add(listener.id));
        final msg = result['message']?.toString() ?? 'We notified ${listener.displayName} that you are waiting.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: const Color(0xFF1F2937),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<ListenerCardModel> get _filteredItems {
    return _items.where((l) {
      // Search text match
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatches = l.displayName.toLowerCase().contains(query);
        final titleMatches = l.professionalTitle.toLowerCase().contains(query);
        final bioMatches = l.bio.toLowerCase().contains(query);
        final catMatches = l.categories.any((c) => c.toLowerCase().contains(query));
        if (!nameMatches && !titleMatches && !bioMatches && !catMatches) {
          return false;
        }
      }

      // Filter chips match
      switch (_selectedFilter) {
        case 'ONLINE':
          return l.presence == 'ONLINE';
        case 'VOICE':
          return l.audioAvailable;
        case 'VIDEO':
          return l.videoAvailable;
        case 'CHAT':
          return l.chatAvailable;
        case 'ALL':
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredItems;
    final onlineCount = _items.where((e) => e.presence == 'ONLINE').length;

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Ambient Warm Radial Glow Orb
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD8C7).withValues(alpha: 0.7),
                    const Color(0xFFFFECE5).withValues(alpha: 0.35),
                    const Color(0xFFFAF5EE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Custom App Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      // Back Button
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderWarm, width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: textDark),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Title & Subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Favourite Listeners',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              _items.isEmpty
                                  ? 'Saved listeners & rates'
                                  : '${_items.length} ${_items.length == 1 ? "listener" : "listeners"} saved · $onlineCount online now',
                              style: const TextStyle(fontSize: 11.5, color: textMuted, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),

                      // Refresh Icon Button
                      InkWell(
                        onTap: () => _load(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderWarm),
                          ),
                          child: const Icon(Icons.refresh_rounded, size: 20, color: primaryOrange),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Bar & Filter Chips (Only show if we have items)
                if (_items.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderWarm),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(fontSize: 13.5, color: textDark, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'Search by name, category or topic...',
                          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w400),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF9CA3AF)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18, color: textMuted),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),

                  // Filter Chips Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(
                      children: [
                        _filterChip('ALL', 'All (${_items.length})', Icons.people_outline_rounded),
                        const SizedBox(width: 8),
                        _filterChip('ONLINE', '🟢 Online ($onlineCount)', null),
                        const SizedBox(width: 8),
                        _filterChip('VOICE', 'Voice Calls', Icons.call_rounded),
                        const SizedBox(width: 8),
                        _filterChip('VIDEO', 'Video Calls', Icons.videocam_rounded),
                        const SizedBox(width: 8),
                        _filterChip('CHAT', 'Private Chat', Icons.chat_bubble_rounded),
                      ],
                    ),
                  ),
                ],

                // Body List
                Expanded(
                  child: _loading
                      ? const LoadingBody()
                      : RefreshIndicator(
                          color: primaryOrange,
                          backgroundColor: Colors.white,
                          onRefresh: () => _load(silent: true),
                          child: filtered.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                                  itemCount: filtered.length,
                                  itemBuilder: (ctx, index) {
                                    final listener = filtered[index];
                                    return _buildListenerCard(listener);
                                  },
                                ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String filterKey, String label, IconData? icon) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? primaryOrange : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primaryOrange : borderWarm,
            width: 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.white : textMuted),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _searchQuery.isNotEmpty || _selectedFilter != 'ALL';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: isFiltered ? const Color(0xFFF3F4F6) : softPeach,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isFiltered ? const Color(0xFFE5E7EB) : const Color(0xFFFCDFD5),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isFiltered ? Icons.search_off_rounded : Icons.favorite_rounded,
                    color: isFiltered ? textMuted : primaryOrange,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isFiltered ? 'No matching listeners' : 'No favourite listeners yet',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
              ),
              const SizedBox(height: 8),
              Text(
                isFiltered
                    ? 'Try adjusting your search terms or filters to find your favourite listeners.'
                    : 'Follow listeners you connect with to keep track of their live availability, full rates, and receive instant online alerts.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              if (isFiltered)
                OutlinedButton(
                  onPressed: () => setState(() {
                    _searchQuery = '';
                    _selectedFilter = 'ALL';
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryOrange,
                    side: const BorderSide(color: primaryOrange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Clear Filters', style: TextStyle(fontWeight: FontWeight.w700)),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text('Discover Top Listeners', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListenerCard(ListenerCardModel listener) {
    final isOnline = listener.presence == 'ONLINE';
    final isBusy = listener.presence == 'BUSY_IN_CALL' || listener.presence == 'BUSY';

    final Color statusColor;
    final String statusLabel;
    final Color statusBg;
    if (isOnline) {
      statusColor = emeraldOnline;
      statusLabel = 'Online Now · Available';
      statusBg = const Color(0xFFE8FDF3);
    } else if (isBusy) {
      statusColor = amberBusy;
      statusLabel = 'Busy in a Consultation';
      statusBg = const Color(0xFFFEF3C7);
    } else {
      statusColor = const Color(0xFF9CA3AF);
      statusLabel = 'Currently Offline';
      statusBg = const Color(0xFFF3F4F6);
    }

    final categories = listener.categories.isNotEmpty
        ? listener.categories
        : ['Empathy', 'Life Advice', 'Relationship Support'];

    final headline = listener.professionalTitle.isNotEmpty
        ? listener.professionalTitle
        : 'Empathetic Verified Listener';

    final bio = listener.bio.isNotEmpty
        ? listener.bio
        : 'Here to listen without judgment. You deserve a safe space to be heard.';

    final isNudged = _nudgedIds.contains(listener.id);
    final isUnfollowing = _unfollowingIds.contains(listener.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderWarm, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: listener)),
          ).then((_) => _load(silent: true)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Avatar + Details + Favourite Heart Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with status beacon dot
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            width: 68,
                            height: 68,
                            child: buildAvatarImage(
                              listener.avatarUrl,
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Center(
                                  child: Text(
                                    listener.displayName.isNotEmpty
                                        ? listener.displayName.substring(0, 1).toUpperCase()
                                        : 'L',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Online / Status Beacon Dot
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: isOnline
                                  ? [
                                      BoxShadow(
                                        color: statusColor.withValues(alpha: 0.6),
                                        blurRadius: 5,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // Info Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Line 1: Name + Verified Icon
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  listener.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: primaryOrange,
                              ),
                              if (listener.isAdult) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: const Color(0xFFFDA4AF),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    '🔞 18+',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Line 2: Headline
                          Text(
                            headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Line 3: Ratings, Review count & Consultations
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 2),
                              Text(
                                listener.rating > 0 ? listener.rating.toStringAsFixed(1) : '4.8',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: textDark),
                              ),
                              Text(
                                ' (${listener.reviewCount > 0 ? listener.reviewCount : 24})',
                                style: const TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 6),
                              Container(width: 3, height: 3, decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(
                                listener.totalConsultations > 0
                                    ? '${listener.totalConsultations} calls'
                                    : '30+ sessions',
                                style: const TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Top-Right: Filled Favourite Heart Button
                    InkWell(
                      onTap: isUnfollowing ? null : () => _unfollow(listener),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECE5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                        ),
                        child: Center(
                          child: isUnfollowing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: primaryOrange),
                                )
                              : const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFEF4444),
                                  size: 19,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Presence Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isOnline
                              ? const Color(0xFF047857)
                              : isBusy
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF4B5563),
                        ),
                      ),
                      if (listener.languages.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(width: 3, height: 3, decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.5), shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        const Icon(Icons.translate_rounded, size: 12, color: textMuted),
                        const SizedBox(width: 4),
                        Text(
                          listener.languages.take(2).join(', '),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: textMuted),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Categories & Specialities Wrap
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: categories.take(3).map((cat) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF5EE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderWarm, width: 0.8),
                      ),
                      child: Text(
                        cat,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF4B5563)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 10),

                // Bio Quote Snippet
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF3F4F6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.format_quote_rounded, size: 16, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          bio,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF6B7280),
                            height: 1.3,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ==========================================
                // ALL SERVICE RATES (Core User Requirement)
                // ==========================================
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE8DF), width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      const Row(
                        children: [
                          Icon(Icons.price_change_outlined, size: 16, color: primaryOrange),
                          SizedBox(width: 6),
                          Text(
                            'All Service Rates',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: textDark,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Per minute billing',
                            style: TextStyle(fontSize: 10.5, color: textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 3 Rate Pillars: Voice, Video, Chat
                      Row(
                        children: [
                          // 1. Voice Call Rate
                          Expanded(
                            child: _buildServiceRateTile(
                              icon: Icons.call_rounded,
                              label: 'Voice',
                              rate: listener.audioRate,
                              isAvailable: listener.audioAvailable,
                              themeColor: primaryOrange,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 2. Video Call Rate
                          Expanded(
                            child: _buildServiceRateTile(
                              icon: Icons.videocam_rounded,
                              label: 'Video',
                              rate: listener.videoRate,
                              isAvailable: listener.videoAvailable,
                              themeColor: purpleVideo,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 3. Text Chat Rate
                          Expanded(
                            child: _buildServiceRateTile(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Chat',
                              rate: listener.chatRate,
                              isAvailable: listener.chatAvailable,
                              themeColor: blueChat,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ==========================================
                // ACTION BUTTONS / QUICK CONNECT
                // ==========================================
                if (isOnline) ...[
                  // 1-Tap Call / Chat Buttons Row
                  Row(
                    children: [
                      // Quick Chat Button
                      if (listener.chatAvailable)
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            onPressed: () => CallLauncher.startDirectCall(context, listener, 'CHAT'),
                            icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                            label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: blueChat,
                              side: const BorderSide(color: Color(0xFFBFDBFE)),
                              backgroundColor: const Color(0xFFEFF6FF),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      if (listener.chatAvailable) const SizedBox(width: 8),

                      // Primary Voice Call Button
                      Expanded(
                        flex: 5,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF7A45), Color(0xFFF95B3D)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: !listener.audioAvailable
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ListenerDetailScreen(listener: listener, initialSessionType: 'AUDIO_CALL'),
                                      ),
                                    ).then((_) => _load(silent: true)),
                            icon: const Icon(Icons.call_rounded, size: 16),
                            label: Text(
                              'Voice Call · ₹${listener.audioRate.toStringAsFixed(0)}/m',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                      if (listener.videoAvailable) const SizedBox(width: 8),

                      // Video Call Button
                      if (listener.videoAvailable)
                        Expanded(
                          flex: 3,
                          child: OutlinedButton.icon(
                            onPressed: () => CallLauncher.startDirectCall(context, listener, 'VIDEO_CALL'),
                            icon: const Icon(Icons.videocam_rounded, size: 16),
                            label: const Text('Video', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: purpleVideo,
                              side: const BorderSide(color: Color(0xFFE9D5FF)),
                              backgroundColor: const Color(0xFFFAF5FF),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ] else if (isBusy) ...[
                  // Busy In Call State
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isNudged ? null : () => _handleNudge(listener),
                          icon: Icon(
                            isNudged ? Icons.check_circle_rounded : Icons.notifications_active_rounded,
                            size: 15,
                            color: isNudged ? emeraldOnline : amberBusy,
                          ),
                          label: Text(
                            isNudged ? 'Nudge Sent!' : 'Busy in Call • Nudge When Free',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isNudged ? emeraldOnline : amberBusy,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isNudged ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                            backgroundColor: isNudged ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: listener)),
                        ).then((_) => _load(silent: true)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textDark,
                          side: const BorderSide(color: borderWarm),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Details ›', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                ] else ...[
                  // Offline State: Nudge + Details Buttons
                  Row(
                    children: [
                      // Nudge when online button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isNudged ? null : () => _handleNudge(listener),
                          icon: Icon(
                            isNudged ? Icons.check_circle_rounded : Icons.notifications_active_rounded,
                            size: 15,
                            color: isNudged ? emeraldOnline : primaryOrange,
                          ),
                          label: Text(
                            isNudged ? 'Nudge Sent!' : 'Nudge When Online',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isNudged ? emeraldOnline : primaryOrange,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isNudged ? const Color(0xFFA7F3D0) : const Color(0xFFFCDFD5)),
                            backgroundColor: isNudged ? const Color(0xFFECFDF5) : const Color(0xFFFFF9F5),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: listener)),
                        ).then((_) => _load(silent: true)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textDark,
                          side: const BorderSide(color: borderWarm),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Details ›', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceRateTile({
    required IconData icon,
    required String label,
    required double rate,
    required bool isAvailable,
    required Color themeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAvailable ? const Color(0xFFF1E6D8) : const Color(0xFFE5E7EB),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isAvailable ? themeColor : textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isAvailable ? textDark : textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '₹${rate.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isAvailable ? textDark : textMuted,
            ),
          ),
          Text(
            '/min',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isAvailable ? textMuted : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: isAvailable ? const Color(0xFFE8FDF3) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isAvailable ? 'Available' : 'Paused',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: isAvailable ? const Color(0xFF059669) : const Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
