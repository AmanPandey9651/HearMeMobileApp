import '../../core/countries_data.dart';
import '../../services/call_launcher.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/hero_banner_card.dart';
import '../../widgets/listener_card_item.dart';
import 'listener_detail_screen.dart';

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
  String filter = 'ALL';
  String categorySlug = '';
  String selectedCountry = 'ALL';
  double? minRating;
  double? maxRate;
  Timer? timer;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  final List<Map<String, String>> quickTopics = const [
    {'name': 'All', 'slug': '', 'icon': '🔆'},
    {'name': 'Heartbreak', 'slug': 'breakup', 'icon': '💔'},
    {'name': 'Loneliness', 'slug': 'loneliness', 'icon': '☁️'},
    {'name': 'Anxiety', 'slug': 'stress', 'icon': '🧠'},
    {'name': 'Advice', 'slug': 'relationship', 'icon': '💬'},
    {'name': 'Career', 'slug': 'career', 'icon': '💼'},
    {'name': 'Vent', 'slug': 'crisis', 'icon': '🌊'},
    {'name': 'Late Night', 'slug': 'late_night', 'icon': '🌙'},
    {'name': '18+ Adult', 'slug': '18+ adult talk', 'icon': '🔞'},
  ];

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
      final data = await context.read<AppController>().api.allListeners(
            query: search.text.trim().isEmpty ? null : search.text.trim(),
            category: categorySlug.isEmpty ? null : categorySlug,
            minRating: minRating,
            maxRate: maxRate,
          );
      if (mounted) setState(() => listeners = data);
    } catch (e) {
      if (mounted && !silent) showError(context, e);
    }
    if (mounted) setState(() => loading = false);
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
      // Fallback: filter list to this modality
      setState(() => filter = modality == 'CHAT' ? 'CHAT' : modality == 'AUDIO_CALL' ? 'VOICE' : 'VIDEO');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Filtered list for available $modality listeners.'),
          backgroundColor: textDark,
        ),
      );
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredCountries = kGlobalCountries.where((c) {
              if (query.isEmpty) return true;
              return c.name.toLowerCase().contains(query.toLowerCase());
            }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.72,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select Country (60+ Worldwide)',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textDark),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (val) => setModalState(() => query = val),
                    decoration: InputDecoration(
                      hintText: 'Search country...',
                      prefixIcon: const Icon(Icons.search_rounded, color: primaryOrange),
                      filled: true,
                      fillColor: const Color(0xFFFAF5EE),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: borderWarm),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: borderWarm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredCountries.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: borderWarm),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return ListTile(
                            leading: const Text('🌐', style: TextStyle(fontSize: 22)),
                            title: const Text('All Countries (Worldwide)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            selected: selectedCountry == 'ALL',
                            selectedTileColor: const Color(0xFFFFF3ED),
                            onTap: () {
                              setState(() => selectedCountry = 'ALL');
                              Navigator.pop(ctx);
                            },
                          );
                        }
                        final c = filteredCountries[i - 1];
                        final isSelected = selectedCountry == c.code;
                        return ListTile(
                          leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                          title: Text(c.name, style: TextStyle(fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500, fontSize: 14, color: isSelected ? primaryOrange : textDark)),
                          selected: isSelected,
                          selectedTileColor: const Color(0xFFFFF3ED),
                          onTap: () {
                            setState(() => selectedCountry = c.code);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _advancedFilters() async {
    final rating = TextEditingController(text: minRating?.toStringAsFixed(1) ?? '');
    final rate = TextEditingController(text: maxRate?.toStringAsFixed(0) ?? '');
    final apply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Listeners',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: rating,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: textDark),
              decoration: InputDecoration(
                labelText: 'Minimum rating (e.g. 4.5)',
                labelStyle: const TextStyle(color: textMuted),
                prefixIcon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                filled: true,
                fillColor: const Color(0xFFFAF5EE),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderWarm),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderWarm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryOrange, width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: textDark),
              decoration: InputDecoration(
                labelText: 'Maximum audio rate ₹/min',
                labelStyle: const TextStyle(color: textMuted),
                prefixIcon: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF10B981)),
                filled: true,
                fillColor: const Color(0xFFFAF5EE),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderWarm),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderWarm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: primaryOrange, width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    rating.clear();
                    rate.clear();
                  },
                  child: const Text('Reset', style: TextStyle(color: textMuted)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (apply == true) {
      final parsedRating = double.tryParse(rating.text.trim());
      final parsedRate = double.tryParse(rate.text.trim());
      setState(() {
        minRating = parsedRating;
        maxRate = parsedRate;
      });
      await _load();
    }
    rating.dispose();
    rate.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var visible = List<ListenerCardModel>.from(listeners);
    if (selectedCountry != 'ALL') {
      visible = visible.where((x) {
        final c = (x.country?.isNotEmpty == true ? x.country! : 'India').trim().toLowerCase();
        final target = selectedCountry.trim().toLowerCase();
        if (target == 'united states' || target == 'usa') {
          return c == 'united states' || c == 'usa' || c == 'us';
        }
        if (target == 'united kingdom' || target == 'uk') {
          return c == 'united kingdom' || c == 'uk';
        }
        return c == target;
      }).toList();
    }
    if (filter == 'ONLINE') visible = visible.where((x) => x.presence == 'ONLINE').toList();
    if (filter == 'VOICE') visible = visible.where((x) => x.audioAvailable).toList();
    if (filter == 'VIDEO') visible = visible.where((x) => x.videoAvailable).toList();
    if (filter == 'CHAT') visible = visible.where((x) => x.chatAvailable).toList();
    if (filter == 'TOP_RATED') {
      visible = visible.where((x) => x.rating >= 4.8).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }
    if (filter == 'LGBTQ') {
      visible = visible.where((x) => x.categories.any((c) => c.toLowerCase().contains('lgbt') || c.toLowerCase().contains('identity'))).toList();
      if (visible.isEmpty) visible = List<ListenerCardModel>.from(listeners);
    }
    if (filter == 'BUDGET') {
      visible = visible.where((x) => x.audioRate > 0 && x.audioRate <= 15).toList()
        ..sort((a, b) => a.audioRate.compareTo(b.audioRate));
    }
    if (filter == 'ADULT_TALK') {
      visible = visible.where((x) => x.isAdult).toList();
    }

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

          // 1. Search Bar (White container, orange search icon, warm border)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
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

          const SizedBox(height: 10),

          // 2. Filter Pills - Row 1 (Topics/Moods with emojis)
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: quickTopics.length,
              itemBuilder: (ctx, idx) {
                final topic = quickTopics[idx];
                final isSelected = categorySlug == topic['slug'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() => categorySlug = topic['slug'] ?? '');
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected ? null : Colors.white,
                        gradient: isSelected
                            ? const LinearGradient(
                                colors: [primaryOrange, secondaryOrange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
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
                          Text(topic['icon'] ?? '', style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(
                            topic['name'] ?? '',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // 2.5 Country Filter Pills
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _BadgePill(
                  label: '🌐 All Countries',
                  isSelected: selectedCountry == 'ALL',
                  onTap: () => setState(() => selectedCountry = 'ALL'),
                ),
                _BadgePill(
                  label: '🇮🇳 India',
                  isSelected: selectedCountry == 'India',
                  onTap: () => setState(() => selectedCountry = 'India'),
                ),
                _BadgePill(
                  label: '🇺🇸 USA',
                  isSelected: selectedCountry == 'United States',
                  onTap: () => setState(() => selectedCountry = 'United States'),
                ),
                _BadgePill(
                  label: '🇬🇧 UK',
                  isSelected: selectedCountry == 'United Kingdom',
                  onTap: () => setState(() => selectedCountry = 'United Kingdom'),
                ),
                _BadgePill(
                  label: '🇨🇦 Canada',
                  isSelected: selectedCountry == 'Canada',
                  onTap: () => setState(() => selectedCountry = 'Canada'),
                ),
                _BadgePill(
                  label: '🇦🇺 Australia',
                  isSelected: selectedCountry == 'Australia',
                  onTap: () => setState(() => selectedCountry = 'Australia'),
                ),
                _BadgePill(
                  label: '🇦🇪 UAE',
                  isSelected: selectedCountry == 'United Arab Emirates',
                  onTap: () => setState(() => selectedCountry = 'United Arab Emirates'),
                ),
                _BadgePill(
                  label: (selectedCountry != 'ALL' && !['India', 'United States', 'United Kingdom', 'Canada', 'Australia', 'United Arab Emirates'].contains(selectedCountry))
                      ? '📍 $selectedCountry'
                      : '🌍 More (60+)...',
                  isSelected: selectedCountry != 'ALL' && !['India', 'United States', 'United Kingdom', 'Canada', 'Australia', 'United Arab Emirates'].contains(selectedCountry),
                  onTap: _showCountryPicker,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 3. Filter Pills - Row 2 (Badges: All (24), Online, Top Rated, LGBTQ+, Budget, Filter)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _BadgePill(
                  label: '✓ All (${listeners.length})',
                  isSelected: filter == 'ALL',
                  onTap: () => setState(() => filter = 'ALL'),
                ),
                _BadgePill(
                  label: '🟢 Online',
                  isSelected: filter == 'ONLINE',
                  onTap: () => setState(() => filter = 'ONLINE'),
                ),
                _BadgePill(
                  label: '⭐ Top Rated',
                  isSelected: filter == 'TOP_RATED',
                  onTap: () => setState(() => filter = 'TOP_RATED'),
                ),
                _BadgePill(
                  label: '👥 LGBTQ+',
                  isSelected: filter == 'LGBTQ',
                  onTap: () => setState(() => filter = 'LGBTQ'),
                ),
                _BadgePill(
                  label: '🔞 18+ Adult',
                  isSelected: filter == 'ADULT_TALK',
                  onTap: () => setState(() => filter = 'ADULT_TALK'),
                ),
                _BadgePill(
                  label: '💰 Budget',
                  isSelected: filter == 'BUDGET',
                  onTap: () => setState(() => filter = 'BUDGET'),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _advancedFilters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: (minRating != null || maxRate != null) ? null : Colors.white,
                        gradient: (minRating != null || maxRate != null)
                            ? const LinearGradient(
                                colors: [primaryOrange, secondaryOrange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (minRating != null || maxRate != null) ? primaryOrange : borderWarm,
                          width: 1.0,
                        ),
                        boxShadow: (minRating != null || maxRate != null)
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
                          Icon(
                            Icons.tune_rounded,
                            size: 14,
                            color: (minRating != null || maxRate != null) ? Colors.white : textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            minRating != null || maxRate != null ? 'Filtered' : 'Filter',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: (minRating != null || maxRate != null) ? Colors.white : const Color(0xFF374151),
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

          const SizedBox(height: 2),

          // 4. Compact Hero Banner Card ("You're Not Alone / Real People. Real Support.")
          HeroBannerCard(
            onChatTap: () => _quickMatchModality('CHAT'),
            onVoiceTap: () => _quickMatchModality('AUDIO_CALL'),
            onVideoTap: () => _quickMatchModality('VIDEO_CALL'),
          ),

          const SizedBox(height: 2),

          // 5. Section Header: "🟢 Available Compassionate Listeners" + "See All →"
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
                        const Text(
                          'Available Compassionate Listeners',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: textDark,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          filter = 'ALL';
                          categorySlug = '';
                          minRating = null;
                          maxRate = null;
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
                          'See All →',
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

          // 6. Listener Cards Feed
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: primaryOrange, strokeWidth: 2)),
            )
          else if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 40, color: textMuted),
                    const SizedBox(height: 10),
                    const Text('No listeners found for this topic.', style: TextStyle(color: textDark, fontSize: 14)),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          categorySlug = '';
                          filter = 'ALL';
                          minRating = null;
                          maxRate = null;
                          search.clear();
                        });
                        _load();
                      },
                      child: const Text('Show all listeners', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else
            ...visible.map(
              (l) => ListenerCardItem(
                listener: l,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: l)),
                ).then((_) => _load(silent: true)),
                onDirectCall: (type) => CallLauncher.startDirectCall(context, l, type),
              ),
            ),
        ],
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BadgePill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const primaryOrange = Color(0xFFF95B3D);
    const borderWarm = Color(0xFFF1E6D8);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? null : Colors.white,
            gradient: isSelected
                ? const LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF7A45)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
