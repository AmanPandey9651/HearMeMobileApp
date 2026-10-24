import '../../core/countries_data.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/hero_banner_card.dart';
import '../../widgets/listener_card_item.dart';
import '../auth/listener_register_screen.dart';
import '../auth/login_screen.dart';
import 'listener_detail_screen.dart';

class PublicHomeScreen extends StatefulWidget {
  const PublicHomeScreen({super.key});

  @override
  State<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  int _navIndex = 0;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Image.asset(
          app.headerLogoAsset,
          height: 27,
          fit: BoxFit.contain,
        ),
        actions: [
          // Solid Orange Pill "Log In" Button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
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
                  child: const Center(
                    child: Text(
                      'Log In',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3-dots popup menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: textDark),
            tooltip: 'Options',
            color: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: borderWarm),
            ),
            onSelected: (val) {
              if (val == 'login_user') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
              } else if (val == 'login_listener') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 1)));
              } else if (val == 'join_listener') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ListenerRegisterScreen()));
              } else if (val == 'how_it_works') {
                setState(() => _navIndex = 1);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'login_user',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 18, color: textMuted),
                    SizedBox(width: 10),
                    Text('Log in as User', style: TextStyle(color: textDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'login_listener',
                child: Row(
                  children: [
                    Icon(Icons.headset_mic_outlined, size: 18, color: textMuted),
                    SizedBox(width: 10),
                    Text('Login as Listener', style: TextStyle(color: textDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'join_listener',
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, size: 18, color: primaryOrange),
                    SizedBox(width: 10),
                    Text('Join as Listener', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: const [
          _PublicExploreView(),
          _PublicHowItWorksView(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: borderWarm, width: 1.0)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Explore Tab (Active with orange circle + dot)
              _BottomNavItem(
                icon: Icons.explore_rounded,
                label: 'Explore',
                isSelected: _navIndex == 0,
                hasActiveDot: true,
                onTap: () => setState(() => _navIndex = 0),
              ),

              // 2. How It Works Tab
              _BottomNavItem(
                icon: Icons.help_outline_rounded,
                label: 'How It Works',
                isSelected: _navIndex == 1,
                hasActiveDot: false,
                onTap: () => setState(() => _navIndex = 1),
              ),

              // 3. Log In Tab
              _BottomNavItem(
                icon: Icons.login_rounded,
                label: 'Log In',
                isSelected: false,
                hasActiveDot: false,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool hasActiveDot;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.hasActiveDot,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFFF95B3D);
    const inactiveColor = Color(0xFF6B7280);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x3DF95B3D),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.explore_rounded, size: 22, color: Colors.white),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(icon, size: 24, color: inactiveColor),
              ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
            if (isSelected && hasActiveDot) ...[
              const SizedBox(height: 3),
              Container(
                width: 4.5,
                height: 4.5,
                decoration: const BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PublicExploreView extends StatefulWidget {
  const _PublicExploreView();

  @override
  State<_PublicExploreView> createState() => _PublicExploreViewState();
}

class _PublicExploreViewState extends State<_PublicExploreView> {
  final search = TextEditingController();
  List<ListenerCardModel> listeners = [];
  bool loading = true;
  String filter = 'ALL';
  String categorySlug = '';
  String selectedCountry = 'ALL';
  Timer? timer;

  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
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
    _load();
    timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
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

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => loading = true);
    try {
      final data = await context.read<AppController>().api.allListeners(
            query: search.text.trim().isEmpty ? null : search.text.trim(),
            category: categorySlug.isEmpty ? null : categorySlug,
          );
      if (mounted) setState(() => listeners = data);
    } catch (e) {
      if (mounted && !silent) showError(context, e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _promptLogin(String listenerName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFECE5),
                boxShadow: [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.shield_rounded, color: primaryOrange, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'Talk with $listenerName',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
            ),
            const SizedBox(height: 4),
            const Text(
              '100% Anonymous • No phone number shared with anyone',
              style: TextStyle(fontSize: 12, color: primaryOrange, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
                },
                icon: const Icon(Icons.login_rounded, size: 17),
                label: const Text('Log In / Sign Up to Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Browsing', style: TextStyle(color: textMuted)),
            ),
          ],
        ),
      ),
    );
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
    if (filter == 'TOP_RATED') {
      visible = visible.where((x) => x.rating >= 4.8).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }
    if (filter == 'LGBTQ') {
      visible = visible.where((x) => x.categories.any((c) => c.toLowerCase().contains('lgbt') || c.toLowerCase().contains('identity'))).toList();
      if (visible.isEmpty) {
        visible = List<ListenerCardModel>.from(listeners);
      }
    }
    if (filter == 'BUDGET') {
      visible = visible.where((x) => x.audioRate > 0 && x.audioRate <= 15).toList()
        ..sort((a, b) => a.audioRate.compareTo(b.audioRate));
    }
    if (filter == 'ADULT_TALK') {
      visible = visible.where((x) => x.isAdult).toList();
    }

    return RefreshIndicator(
      color: primaryOrange,
      backgroundColor: Colors.white,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 10),

          // 1. Search Bar (White rounded container, orange search icon, placeholder)
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
                                colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
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

          // 3. Filter Pills - Row 2 (Badges: All (24), Online, Top Rated, LGBTQ+, Budget)
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
              ],
            ),
          ),

          const SizedBox(height: 6),

          // 4. Hero Banner Card ("You're Not Alone / Real People. Real Support.")
          HeroBannerCard(
            onChatTap: () => _promptLogin('a listener for Chat'),
            onVoiceTap: () => _promptLogin('a listener for Voice Call'),
            onVideoTap: () => _promptLogin('a listener for Video Call'),
          ),

          const SizedBox(height: 6),

          // 5. Section Header: "🟢 Available Compassionate Listeners" + "See All →"
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
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
                isPublic: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: l)),
                ).then((_) => _load(silent: true)),
                onConnect: () => _promptLogin(l.displayName),
              ),
            ),
        ],
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
                    colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
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

class _PublicHowItWorksView extends StatelessWidget {
  const _PublicHowItWorksView();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    const primaryOrange = Color(0xFFF95B3D);
    const textDark = Color(0xFF111827);
    const textMuted = Color(0xFF6B7280);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFECE5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.help_outline_rounded, color: primaryOrange, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How ${app.activeBrandName} Works',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
                ),
                Text(
                  '100% anonymous & judgment-free',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),

        const _AppStepTile(
          step: '1',
          icon: Icons.search_rounded,
          title: 'Pick a Listener',
          description: 'Browse verified empathetic listeners by topic, rating, and online availability.',
        ),
        const SizedBox(height: 10),

        const _AppStepTile(
          step: '2',
          icon: Icons.shield_rounded,
          title: 'Zero Identity Revealed',
          description: 'No real names or phone numbers are ever shared. Voice, video, and chat are end-to-end private.',
        ),
        const SizedBox(height: 10),

        const _AppStepTile(
          step: '3',
          icon: Icons.favorite_rounded,
          title: 'Feel Supported',
          description: 'Talk freely, vent, or share whatever is on your heart. Compassionate ears are ready right now.',
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Get Started Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),

        const SizedBox(height: 36),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                app.headerLogoAsset,
                height: 36,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 10),
              const Text(
                'Anonymous Emotional Wellness & Healing Support',
                style: TextStyle(fontSize: 12.5, color: textMuted, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                '100% Zero-PII • Confidential • Empathetic Listeners',
                style: TextStyle(fontSize: 11, color: textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AppStepTile extends StatelessWidget {
  final String step;
  final IconData icon;
  final String title;
  final String description;

  const _AppStepTile({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    const primaryOrange = Color(0xFFF95B3D);
    const borderWarm = Color(0xFFF1E6D8);
    const textDark = Color(0xFF111827);
    const textMuted = Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderWarm),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(icon, color: primaryOrange, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$step. $title',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textDark),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12.5, color: textMuted, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
