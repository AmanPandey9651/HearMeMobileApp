import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/call_launcher.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/hero_banner_card.dart';
import '../../widgets/listener_card_item.dart';
import 'listener_detail_screen.dart';
import 'listener_filter_screen.dart';

class CallerHomeScreen extends StatefulWidget {
  const CallerHomeScreen({super.key});

  @override
  State<CallerHomeScreen> createState() => _CallerHomeScreenState();
}

class _CallerHomeScreenState extends State<CallerHomeScreen> {
  final search = TextEditingController();
  List<ListenerCardModel> listeners = [];
  List<Map<String, dynamic>> categories = [];
  bool loading = true;
  ListenerFilterCriteria filterCriteria = ListenerFilterCriteria();
  Timer? timer;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
    timer = Timer.periodic(const Duration(seconds: 12), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await context.read<AppController>().api.categories();
      if (!mounted) return;
      setState(() => categories = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final cat = filterCriteria.categorySlug.isNotEmpty ? filterCriteria.categorySlug : null;
      final rMin = filterCriteria.topRated ? 4.8 : null;
      final rMax = filterCriteria.budget ? 15.0 : null;
      final data = await context.read<AppController>().api.allListeners(
            query: search.text.trim().isEmpty ? null : search.text.trim(),
            category: cat,
            minRating: rMin,
            maxRate: rMax,
          );
      if (mounted) setState(() => listeners = data);
    } catch (e) {
      if (mounted && !silent) showError(context, e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _openFilterScreen() async {
    final res = await Navigator.push<ListenerFilterCriteria>(
      context,
      MaterialPageRoute(
        builder: (_) => ListenerFilterScreen(
          initialCriteria: filterCriteria,
          allListeners: listeners,
        ),
      ),
    );
    if (res != null && mounted) {
      setState(() {
        filterCriteria = res;
      });
      _load();
    }
  }

  void _quickMatchModality(String modality) {
    var candidates = listeners.where((x) => x.presence == 'ONLINE').toList();
    if (modality == 'CHAT') candidates = candidates.where((x) => x.chatAvailable).toList();
    if (modality == 'AUDIO_CALL') candidates = candidates.where((x) => x.audioAvailable).toList();
    if (modality == 'VIDEO_CALL') candidates = candidates.where((x) => x.videoAvailable).toList();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.rating.compareTo(a.rating));
      CallLauncher.startDirectCall(context, candidates.first, modality);
    } else {
      // Filter list to this modality
      setState(() {
        filterCriteria.modality = modality == 'CHAT'
            ? 'CHAT'
            : modality == 'AUDIO_CALL'
                ? 'VOICE'
                : 'VIDEO';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filtered list for available $modality listeners.'),
          backgroundColor: textDark,
        ),
      );
    }
  }

  Widget _buildActiveFilterPill(String label, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6EE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: primaryOrange,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 13, color: primaryOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var visible = List<ListenerCardModel>.from(listeners);

    // 1. Country Filter
    if (filterCriteria.country != 'ALL') {
      visible = visible.where((x) {
        final c = (x.country?.isNotEmpty == true ? x.country! : 'India').trim().toLowerCase();
        final target = filterCriteria.country.trim().toLowerCase();
        if (target == 'united states' || target == 'usa') {
          return c == 'united states' || c == 'usa' || c == 'us';
        }
        if (target == 'united kingdom' || target == 'uk') {
          return c == 'united kingdom' || c == 'uk';
        }
        return c == target;
      }).toList();
    }

    // 2. Availability (Online Now)
    if (filterCriteria.status == 'ONLINE') {
      visible = visible.where((x) => x.presence == 'ONLINE').toList();
    }

    // 3. Modality (Voice, Video, Chat)
    if (filterCriteria.modality == 'VOICE') {
      visible = visible.where((x) => x.audioAvailable).toList();
    } else if (filterCriteria.modality == 'VIDEO') {
      visible = visible.where((x) => x.videoAvailable).toList();
    } else if (filterCriteria.modality == 'CHAT') {
      visible = visible.where((x) => x.chatAvailable).toList();
    }

    // 4. Topic Slug
    if (filterCriteria.categorySlug.isNotEmpty) {
      if (filterCriteria.categorySlug == '18+ adult talk') {
        visible = visible.where((x) => x.isAdult).toList();
      } else {
        visible = visible.where((x) => x.categories.any(
            (cat) => cat.toLowerCase().contains(filterCriteria.categorySlug.toLowerCase()))).toList();
      }
    }

    // 5. Top Rated
    if (filterCriteria.topRated) {
      visible = visible.where((x) => x.rating >= 4.8).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }

    // 6. Budget
    if (filterCriteria.budget) {
      visible = visible.where((x) => x.audioRate > 0 && x.audioRate <= 15).toList()
        ..sort((a, b) => a.audioRate.compareTo(b.audioRate));
    }

    // 7. Adult Talk
    if (filterCriteria.adultTalk) {
      visible = visible.where((x) => x.isAdult).toList();
    }

    // 8. Priority Ordering: Star Listeners appear first while preserving secondary ordering
    visible.sort((a, b) {
      if (a.isStarListener != b.isStarListener) {
        return a.isStarListener ? -1 : 1;
      }
      return 0;
    });

    return ColoredBox(
      color: bgCream,
      child: RefreshIndicator(
        color: primaryOrange,
        backgroundColor: Colors.white,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(height: 10),

            // 1. Search Bar & Dedicated Filters Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  // Search Box
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _load(),
                        style: const TextStyle(fontSize: 14, color: textDark),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          prefixIcon: const Icon(Icons.search_rounded, size: 22, color: primaryOrange),
                          hintText: 'Search listeners, topics...',
                          hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: borderWarm, width: 1.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: borderWarm, width: 1.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: primaryOrange, width: 1.2),
                          ),
                          suffixIcon: search.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16, color: textMuted),
                                  onPressed: () {
                                    search.clear();
                                    _load();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dedicated Filters Button with Active Badge
                  InkWell(
                    onTap: _openFilterScreen,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: filterCriteria.hasActiveFilters ? const Color(0xFFFFF6EE) : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: filterCriteria.hasActiveFilters ? primaryOrange : borderWarm,
                          width: filterCriteria.hasActiveFilters ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: filterCriteria.hasActiveFilters ? primaryOrange : textDark,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: filterCriteria.hasActiveFilters ? FontWeight.w800 : FontWeight.w700,
                              color: filterCriteria.hasActiveFilters ? primaryOrange : textDark,
                            ),
                          ),
                          if (filterCriteria.hasActiveFilters) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: const BoxDecoration(
                                color: primaryOrange,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${filterCriteria.activeFilterCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Active Filter Chips Row (Visible only when filters are active)
            if (filterCriteria.hasActiveFilters) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    if (filterCriteria.status == 'ONLINE')
                      _buildActiveFilterPill(
                        '🟢 Online Now',
                        () {
                          setState(() => filterCriteria.status = 'ALL');
                          _load();
                        },
                      ),
                    if (filterCriteria.modality != 'ALL')
                      _buildActiveFilterPill(
                        filterCriteria.modality == 'VOICE'
                            ? '📞 Voice Call'
                            : filterCriteria.modality == 'VIDEO'
                                ? '📹 Video Call'
                                : '💬 Chat',
                        () {
                          setState(() => filterCriteria.modality = 'ALL');
                          _load();
                        },
                      ),
                    if (filterCriteria.country != 'ALL')
                      _buildActiveFilterPill(
                        '📍 ${filterCriteria.country}',
                        () {
                          setState(() => filterCriteria.country = 'ALL');
                          _load();
                        },
                      ),
                    if (filterCriteria.categorySlug.isNotEmpty)
                      _buildActiveFilterPill(
                        '🔆 ${filterCriteria.categorySlug.replaceAll('_', ' ')}',
                        () {
                          setState(() => filterCriteria.categorySlug = '');
                          _load();
                        },
                      ),
                    if (filterCriteria.topRated)
                      _buildActiveFilterPill(
                        '⭐ 4.8+ Stars',
                        () {
                          setState(() => filterCriteria.topRated = false);
                          _load();
                        },
                      ),
                    if (filterCriteria.budget)
                      _buildActiveFilterPill(
                        '🏷️ Under ₹15/m',
                        () {
                          setState(() => filterCriteria.budget = false);
                          _load();
                        },
                      ),
                    if (filterCriteria.adultTalk)
                      _buildActiveFilterPill(
                        '🔞 18+ Adult',
                        () {
                          setState(() => filterCriteria.adultTalk = false);
                          _load();
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () {
                          setState(() => filterCriteria.reset());
                          _load();
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderWarm),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.refresh_rounded, size: 13, color: textMuted),
                              SizedBox(width: 4),
                              Text(
                                'Clear All',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 2. Compact Hero Banner Card ("You're Not Alone / Real People. Real Support.")
            HeroBannerCard(
              onChatTap: () => _quickMatchModality('CHAT'),
              onVoiceTap: () => _quickMatchModality('AUDIO_CALL'),
              onVideoTap: () => _quickMatchModality('VIDEO_CALL'),
            ),

            const SizedBox(height: 4),

            // 3. Section Header: "Available Compassionate Listeners" + "See All / Reset"
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF10B981),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            filterCriteria.hasActiveFilters
                                ? 'Filtered Listeners (${visible.length})'
                                : 'Available Compassionate Listeners',
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: textDark,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                      if (filterCriteria.hasActiveFilters)
                        InkWell(
                          onTap: () {
                            setState(() {
                              filterCriteria.reset();
                              search.clear();
                            });
                            _load();
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: primaryOrange,
                                width: 1.0,
                              ),
                            ),
                            child: const Text(
                              'Reset ✕',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: primaryOrange,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Connect instantly via chat, voice, or video. 100% private & judgment-free.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // 4. Listener Cards Feed with 3 Direct Calling/Chat Buttons on each card
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: primaryOrange),
                ),
              )
            else if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.person_search_rounded, size: 52, color: textMuted.withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    const Text(
                      'No listeners found matching criteria',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textDark),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Try adjusting or resetting your filters to see more listeners.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      onPressed: () {
                        setState(() {
                          filterCriteria.reset();
                          search.clear();
                        });
                        _load();
                      },
                      child: const Text('Reset All Filters', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              )
            else
              ...visible.map(
                (l) => ListenerCardItem(
                  listener: l,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: l)),
                  ),
                  onDirectCall: (type) => CallLauncher.startDirectCall(context, l, type),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
