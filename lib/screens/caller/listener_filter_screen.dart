import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../core/countries_data.dart';
import '../../models/app_models.dart';

class ListenerFilterCriteria {
  String status; // 'ALL' | 'ONLINE'
  String modality; // 'ALL' | 'VOICE' | 'VIDEO' | 'CHAT'
  String categorySlug; // '' or specific category slug
  String country; // 'ALL' or country name
  bool topRated; // rating >= 4.8
  bool budget; // audioRate <= 15
  bool adultTalk; // isAdult == true

  ListenerFilterCriteria({
    this.status = 'ALL',
    this.modality = 'ALL',
    this.categorySlug = '',
    this.country = 'ALL',
    this.topRated = false,
    this.budget = false,
    this.adultTalk = false,
  });

  bool get hasActiveFilters =>
      status != 'ALL' ||
      modality != 'ALL' ||
      categorySlug.isNotEmpty ||
      country != 'ALL' ||
      topRated ||
      budget ||
      adultTalk;

  int get activeFilterCount {
    int count = 0;
    if (status != 'ALL') count++;
    if (modality != 'ALL') count++;
    if (categorySlug.isNotEmpty) count++;
    if (country != 'ALL') count++;
    if (topRated) count++;
    if (budget) count++;
    if (adultTalk) count++;
    return count;
  }

  void reset() {
    status = 'ALL';
    modality = 'ALL';
    categorySlug = '';
    country = 'ALL';
    topRated = false;
    budget = false;
    adultTalk = false;
  }

  ListenerFilterCriteria copy() {
    return ListenerFilterCriteria(
      status: status,
      modality: modality,
      categorySlug: categorySlug,
      country: country,
      topRated: topRated,
      budget: budget,
      adultTalk: adultTalk,
    );
  }
}

class ListenerFilterScreen extends StatefulWidget {
  final ListenerFilterCriteria initialCriteria;
  final List<ListenerCardModel> allListeners;

  const ListenerFilterScreen({
    super.key,
    required this.initialCriteria,
    required this.allListeners,
  });

  @override
  State<ListenerFilterScreen> createState() => _ListenerFilterScreenState();
}

class _ListenerFilterScreenState extends State<ListenerFilterScreen> {
  late ListenerFilterCriteria criteria;

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  final List<Map<String, String>> topics = const [
    {'name': 'All Topics', 'slug': '', 'icon': '🔆'},
    {'name': 'Heartbreak & Breakup', 'slug': 'breakup', 'icon': '💔'},
    {'name': 'Loneliness & Void', 'slug': 'loneliness', 'icon': '☁️'},
    {'name': 'Anxiety & Stress', 'slug': 'stress', 'icon': '🧠'},
    {'name': 'Relationship Advice', 'slug': 'relationship', 'icon': '💬'},
    {'name': 'Career & Studies', 'slug': 'career', 'icon': '💼'},
    {'name': 'Venting & Frustration', 'slug': 'crisis', 'icon': '🌊'},
    {'name': 'Late Night Talks', 'slug': 'late_night', 'icon': '🌙'},
    {'name': '18+ Adult Talk', 'slug': '18+ adult talk', 'icon': '🔞'},
  ];

  final List<Map<String, String>> topCountries = const [
    {'name': 'All Countries', 'val': 'ALL', 'flag': '🌐'},
    {'name': 'India', 'val': 'India', 'flag': '🇮🇳'},
    {'name': 'USA', 'val': 'United States', 'flag': '🇺🇸'},
    {'name': 'UK', 'val': 'United Kingdom', 'flag': '🇬🇧'},
    {'name': 'Canada', 'val': 'Canada', 'flag': '🇨🇦'},
    {'name': 'Australia', 'val': 'Australia', 'flag': '🇦🇺'},
    {'name': 'UAE', 'val': 'United Arab Emirates', 'flag': '🇦🇪'},
  ];

  @override
  void initState() {
    super.initState();
    criteria = widget.initialCriteria.copy();
  }

  int get matchingCount {
    var list = List<ListenerCardModel>.from(widget.allListeners);
    if (criteria.country != 'ALL') {
      list = list.where((x) {
        final c = (x.country?.isNotEmpty == true ? x.country! : 'India').trim().toLowerCase();
        final target = criteria.country.trim().toLowerCase();
        if (target == 'united states' || target == 'usa') {
          return c == 'united states' || c == 'usa' || c == 'us';
        }
        if (target == 'united kingdom' || target == 'uk') {
          return c == 'united kingdom' || c == 'uk';
        }
        return c == target;
      }).toList();
    }
    if (criteria.status == 'ONLINE') {
      list = list.where((x) => x.presence == 'ONLINE').toList();
    }
    if (criteria.modality == 'VOICE') {
      list = list.where((x) => x.audioAvailable).toList();
    } else if (criteria.modality == 'VIDEO') {
      list = list.where((x) => x.videoAvailable).toList();
    } else if (criteria.modality == 'CHAT') {
      list = list.where((x) => x.chatAvailable).toList();
    }
    if (criteria.categorySlug.isNotEmpty) {
      if (criteria.categorySlug == '18+ adult talk') {
        list = list.where((x) => x.isAdult).toList();
      } else {
        list = list.where((x) => x.categories.any((cat) => cat.toLowerCase().contains(criteria.categorySlug.toLowerCase()))).toList();
      }
    }
    if (criteria.topRated) {
      list = list.where((x) => x.rating >= 4.8).toList();
    }
    if (criteria.budget) {
      list = list.where((x) => x.audioRate > 0 && x.audioRate <= 15).toList();
    }
    if (criteria.adultTalk) {
      list = list.where((x) => x.isAdult).toList();
    }
    return list.length;
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
                      hintText: 'Search countries...',
                      hintStyle: const TextStyle(fontSize: 13, color: textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: primaryOrange),
                      filled: true,
                      fillColor: bgCream,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      itemCount: filteredCountries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: borderWarm),
                      itemBuilder: (context, index) {
                        final country = filteredCountries[index];
                        final isSel = criteria.country.toLowerCase() == country.name.toLowerCase();
                        return ListTile(
                          dense: true,
                          title: Text(
                            country.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? primaryOrange : textDark,
                            ),
                          ),
                          trailing: isSel
                              ? const Icon(Icons.check_circle_rounded, color: primaryOrange, size: 18)
                              : null,
                          onTap: () {
                            setState(() => criteria.country = country.name);
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

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 16),
      child: Row(
        children: [
          Icon(icon, size: 17, color: primaryOrange),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: textDark,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = matchingCount;
    final activeCount = criteria.activeFilterCount;

    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: textDark, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text(
              'Filter Listeners',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textDark,
                letterSpacing: -0.4,
              ),
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (criteria.hasActiveFilters)
            TextButton(
              onPressed: () => setState(() => criteria.reset()),
              child: const Text(
                'Reset All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: primaryOrange,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderWarm, height: 1),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
            children: [
              // 1. Availability Section
              _buildSectionTitle('Availability', Icons.circle_outlined),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'All Listeners',
                      subtitle: 'Browse all verified profiles',
                      icon: Icons.people_outline_rounded,
                      isSelected: criteria.status == 'ALL',
                      onTap: () => setState(() => criteria.status = 'ALL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'Online Now',
                      subtitle: 'Ready to connect right now',
                      icon: Icons.bolt_rounded,
                      badge: 'Instant',
                      isSelected: criteria.status == 'ONLINE',
                      onTap: () => setState(() => criteria.status = 'ONLINE'),
                    ),
                  ),
                ],
              ),

              // 2. Modality Section
              _buildSectionTitle('Connect via', Icons.call_outlined),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'Any Mode',
                      subtitle: 'Voice, video or chat',
                      icon: Icons.all_inclusive_rounded,
                      isSelected: criteria.modality == 'ALL',
                      onTap: () => setState(() => criteria.modality = 'ALL'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'Voice Call',
                      subtitle: 'Audio conversation',
                      icon: Icons.phone_rounded,
                      isSelected: criteria.modality == 'VOICE',
                      onTap: () => setState(() => criteria.modality = 'VOICE'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'Chat Message',
                      subtitle: 'Live text messaging',
                      icon: Icons.chat_bubble_outline_rounded,
                      isSelected: criteria.modality == 'CHAT',
                      onTap: () => setState(() => criteria.modality = 'CHAT'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildChoiceCard(
                      label: 'Video Call',
                      subtitle: 'Face-to-face video',
                      icon: Icons.videocam_outlined,
                      isSelected: criteria.modality == 'VIDEO',
                      onTap: () => setState(() => criteria.modality = 'VIDEO'),
                    ),
                  ),
                ],
              ),

              // 3. Topics & Support Areas
              _buildSectionTitle('Topic & Support Area', Icons.auto_awesome_rounded),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topics.map((t) {
                  final isSelected = criteria.categorySlug == t['slug'];
                  return InkWell(
                    onTap: () => setState(() => criteria.categorySlug = t['slug']!),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryOrange : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primaryOrange : borderWarm,
                          width: 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: primaryOrange.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t['icon']!, style: const TextStyle(fontSize: 13.5)),
                          const SizedBox(width: 6),
                          Text(
                            t['name']!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              // 4. Country & Region
              _buildSectionTitle('Country & Region', Icons.public_rounded),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...topCountries.map((c) {
                    final isSelected = criteria.country == c['val'];
                    return InkWell(
                      onTap: () => setState(() => criteria.country = c['val']!),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? primaryOrange : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? primaryOrange : borderWarm,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(c['flag']!, style: const TextStyle(fontSize: 13.5)),
                            const SizedBox(width: 5),
                            Text(
                              c['name']!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? Colors.white : textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  InkWell(
                    onTap: _showCountryPicker,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: (criteria.country != 'ALL' && !topCountries.any((c) => c['val'] == criteria.country))
                            ? primaryOrange
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (criteria.country != 'ALL' && !topCountries.any((c) => c['val'] == criteria.country))
                              ? primaryOrange
                              : borderWarm,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌍', style: TextStyle(fontSize: 13.5)),
                          const SizedBox(width: 5),
                          Text(
                            (criteria.country != 'ALL' && !topCountries.any((c) => c['val'] == criteria.country))
                                ? criteria.country
                                : 'More Countries (60+)...',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: (criteria.country != 'ALL' && !topCountries.any((c) => c['val'] == criteria.country))
                                  ? Colors.white
                                  : textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 5. Ratings & Pricing Preferences
              _buildSectionTitle('Experience & Rates', Icons.star_outline_rounded),
              _buildCheckboxTile(
                title: 'Top Rated Listeners Only',
                subtitle: 'Listeners with 4.8★ rating or higher',
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFF59E0B),
                value: criteria.topRated,
                onChanged: (val) => setState(() => criteria.topRated = val ?? false),
              ),
              const SizedBox(height: 8),
              _buildCheckboxTile(
                title: 'Budget Friendly',
                subtitle: 'Call rate ₹15/minute or less',
                icon: Icons.savings_outlined,
                iconColor: const Color(0xFF10B981),
                value: criteria.budget,
                onChanged: (val) => setState(() => criteria.budget = val ?? false),
              ),
              const SizedBox(height: 8),
              _buildCheckboxTile(
                title: '18+ Adult Talk Enabled',
                subtitle: 'Show verified listeners open to mature adult topics',
                icon: Icons.explicit_rounded,
                iconColor: Colors.deepPurple,
                value: criteria.adultTalk,
                onChanged: (val) => setState(() => criteria.adultTalk = val ?? false),
              ),
            ],
          ),

          // Bottom Floating Apply Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: borderWarm)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    if (criteria.hasActiveFilters) ...[
                      OutlinedButton(
                        onPressed: () => setState(() => criteria.reset()),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: borderWarm),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        child: const Text(
                          'Clear',
                          style: TextStyle(fontWeight: FontWeight.w700, color: textMuted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, criteria);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          count == 0
                              ? 'Show 0 Listeners (Clear Filters)'
                              : 'Show $count ${count == 1 ? 'Listener' : 'Listeners'}',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
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
  }

  Widget _buildChoiceCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF6EE) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryOrange : borderWarm,
            width: isSelected ? 1.5 : 1.0,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? primaryOrange : textMuted,
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: primaryOrange),
                    ),
                  )
                else if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: primaryOrange, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: isSelected ? primaryOrange : textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: value ? const Color(0xFFFFF6EE) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? primaryOrange : borderWarm,
            width: value ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: value ? primaryOrange : textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: textMuted),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: primaryOrange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
          ],
        ),
      ),
    );
  }
}
