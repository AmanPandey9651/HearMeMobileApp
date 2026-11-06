import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../widgets/common_widgets.dart';

class ListenerProfileScreen extends StatefulWidget {
  const ListenerProfileScreen({super.key});

  @override
  State<ListenerProfileScreen> createState() => _ListenerProfileScreenState();
}

class _ListenerProfileScreenState extends State<ListenerProfileScreen> {
  Map<String, dynamic>? p;
  Map<String, dynamic>? limits;
  List<Map<String, dynamic>> allCategories = [];
  List<Map<String, dynamic>> allLanguages = [];
  final selectedCategoryIds = <String>{};
  final selectedLanguageCodes = <String>{};

  bool loading = true, busy = false;
  final first = TextEditingController();
  final last = TextEditingController();
  final phone = TextEditingController();
  final gender = TextEditingController();
  final hobbies = TextEditingController();
  final title = TextEditingController();
  final bio = TextEditingController();
  final experience = TextEditingController();
  final audio = TextEditingController();
  final video = TextEditingController();
  final chat = TextEditingController();
  final minDuration = TextEditingController();
  final maxDuration = TextEditingController();
  final noticeHours = TextEditingController();
  final advanceDays = TextEditingController();
  String consultationType = 'BOTH';
  String? avatarUrl;
  bool chatAvailable = true;
  bool audioAvailable = true;
  bool videoAvailable = true;

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      first,
      last,
      phone,
      gender,
      hobbies,
      title,
      bio,
      experience,
      audio,
      video,
      chat,
      minDuration,
      maxDuration,
      noticeHours,
      advanceDays
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final values = await Future.wait<dynamic>([
        api.myExpertProfile(),
        api.categories(),
        api.languages(),
        api.rateLimits().catchError((_) => <String, dynamic>{}),
      ]);
      p = Map<String, dynamic>.from(values[0] as Map);
      allCategories = (values[1] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      allLanguages = (values[2] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      limits = Map<String, dynamic>.from(values[3] as Map);
      final m = p!;

      final appUser = context.read<AppController>().user;
      final profileName = '${m['name'] ?? ''}'.trim();
      final parts = profileName.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      first.text = appUser?.firstName.isNotEmpty == true ? appUser!.firstName : (parts.isNotEmpty ? parts.first : '');
      last.text = appUser?.lastName.isNotEmpty == true ? appUser!.lastName : (parts.length > 1 ? parts.sublist(1).join(' ') : '');
      phone.text = '${m['phoneNumber'] ?? appUser?.phoneNumber ?? ''}';
      gender.text = '${m['gender'] ?? appUser?.gender ?? 'Female'}';
      if (gender.text.isEmpty) gender.text = 'Female';
      hobbies.text = '${m['hobbies'] ?? appUser?.hobbies ?? ''}';
      title.text = '${m['professionalTitle'] ?? ''}';
      bio.text = '${m['bio'] ?? ''}';
      experience.text = '${m['experienceYears'] ?? 0}';
      audio.text = '${m['ratePerMinute'] ?? m['audioRatePerMinute'] ?? 0}';
      video.text = '${m['videoRatePerMinute'] ?? 0}';
      chat.text = '${m['chatRatePerMinute'] ?? 0}';
      minDuration.text = '${m['minDurationMinutes'] ?? 5}';
      maxDuration.text = '${m['maxDurationMinutes'] ?? 60}';
      noticeHours.text = '${m['noticePeriodHours'] ?? 0}';
      advanceDays.text = '${m['maxAdvanceDays'] ?? 30}';
      consultationType = '${m['consultationType'] ?? 'BOTH'}';
      avatarUrl = m['avatarUrl']?.toString();
      chatAvailable = m['chatAvailable'] != false;
      audioAvailable = m['audioAvailable'] != false;
      videoAvailable = m['videoAvailable'] != false;

      selectedCategoryIds.clear();
      for (final item in (m['categories'] as List?) ?? const []) {
        if (item is Map) {
          final id = item['id']?.toString();
          if (id != null && id.isNotEmpty) selectedCategoryIds.add(id);
        } else {
          selectedCategoryIds.add(item.toString());
        }
      }
      selectedLanguageCodes.clear();
      for (final item in (m['languages'] as List?) ?? const []) {
        if (item is Map) {
          final code = item['code']?.toString();
          if (code != null && code.isNotEmpty) selectedLanguageCodes.add(code);
        } else {
          selectedLanguageCodes.add(item.toString());
        }
      }
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  bool get _isInternational {
    final c = (p?['country'] ?? context.read<AppController>().user?.country ?? '').toString().trim().toLowerCase();
    return c.isNotEmpty && c != 'india' && c != 'in';
  }

  double _limit(String key, double fallback) {
    if (_isInternational) {
      final intlKey = key.replaceFirst('min', 'minInternational').replaceFirst('max', 'maxInternational');
      final val = (limits?[intlKey] as num?)?.toDouble();
      if (val != null) return val;
      if (key == 'minAudioRatePerMinute') return 20.0;
      if (key == 'maxAudioRatePerMinute') return 150.0;
      if (key == 'minVideoRatePerMinute') return 35.0;
      if (key == 'maxVideoRatePerMinute') return 250.0;
      if (key == 'minChatRatePerMinute') return 10.0;
      if (key == 'maxChatRatePerMinute') return 80.0;
    }
    return (limits?[key] as num?)?.toDouble() ?? fallback;
  }

  Future<void> _photo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1800);
    if (x == null) return;
    final file = File(x.path);
    final bytes = await file.length();
    if (bytes > 5 * 1024 * 1024) {
      if (mounted) showError(context, 'Please choose an image under 5 MB.');
      return;
    }
    try {
      final r = await context.read<AppController>().api.uploadMedia(file, folder: 'listeners');
      avatarUrl = '${r['secureUrl'] ?? r['url'] ?? ''}';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _validateRates(double a, double v, double c) {
    final amin = _limit('minAudioRatePerMinute', 5), amax = _limit('maxAudioRatePerMinute', 50);
    final vmin = _limit('minVideoRatePerMinute', 10), vmax = _limit('maxVideoRatePerMinute', 100);
    final cmin = _limit('minChatRatePerMinute', 2), cmax = _limit('maxChatRatePerMinute', 30);
    final tier = _isInternational ? 'International' : 'Domestic';
    if (a < amin || a > amax) throw Exception('Audio rate must be between ₹$amin and ₹$amax per minute ($tier).');
    if (v < vmin || v > vmax) throw Exception('Video rate must be between ₹$vmin and ₹$vmax per minute ($tier).');
    if (c < cmin || c > cmax) throw Exception('Chat rate must be between ₹$cmin and ₹$cmax per minute ($tier).');
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      if (first.text.trim().isEmpty) throw Exception('First name cannot be empty.');
      if (title.text.trim().isEmpty) throw Exception('Professional title is required.');
      if (bio.text.trim().isEmpty) throw Exception('Biography cannot be empty.');
      if (selectedLanguageCodes.isEmpty) throw Exception('Select at least one language.');
      if (selectedCategoryIds.isEmpty) throw Exception('Select at least one topic/category.');

      final a = double.tryParse(audio.text) ?? 0;
      final v = double.tryParse(video.text) ?? 0;
      final c = double.tryParse(chat.text) ?? 0;
      _validateRates(a, v, c);

      final data = <String, dynamic>{
        'firstName': first.text.trim(),
        'lastName': last.text.trim(),
        'phoneNumber': phone.text.trim(),
        'avatarUrl': avatarUrl ?? '',
        'gender': gender.text.trim(),
        'hobbies': hobbies.text.trim(),
        'professionalTitle': title.text.trim(),
        'bio': bio.text.trim(),
        'experienceYears': int.tryParse(experience.text) ?? 0,
        'ratePerMinute': a,
        'videoRatePerMinute': v,
        'chatRatePerMinute': c,
        'currency': 'INR',
        'consultationType': consultationType,
        'minDurationMinutes': int.tryParse(minDuration.text) ?? 5,
        'maxDurationMinutes': int.tryParse(maxDuration.text) ?? 60,
        'noticePeriodHours': int.tryParse(noticeHours.text) ?? 0,
        'maxAdvanceDays': int.tryParse(advanceDays.text) ?? 30,
        'categoryIds': selectedCategoryIds.toList(),
        'languageCodes': selectedLanguageCodes.toList(),
        'chatAvailable': chatAvailable,
        'audioAvailable': audioAvailable,
        'videoAvailable': videoAvailable,
      };
      p = await context.read<AppController>().api.updateExpertProfile(data);
      try {
        await context.read<AppController>().api.updateModalities(
              chatAvailable: chatAvailable,
              audioAvailable: audioAvailable,
              videoAvailable: videoAvailable,
            );
      } catch (_) {}
      try {
        await context.read<AppController>().refreshUser();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Profile and preferences saved successfully.'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(backgroundColor: bgCream, body: LoadingBody());

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Top-right warm peach ambient glow orb
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
            child: RefreshIndicator(
              color: primaryOrange,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  // Title Header
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Profile Photo with Camera Badge matching Screenshot 2
                  Center(
                    child: GestureDetector(
                      onTap: _photo,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                              Container(
                                width: 108,
                                height: 108,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryOrange.withValues(alpha: 0.16),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: buildAvatarImage(
                                    avatarUrl,
                                    width: 108,
                                    height: 108,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: softPeach,
                                      child: const Center(
                                        child: Icon(Icons.person_rounded, size: 54, color: primaryOrange),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [primaryOrange, secondaryOrange],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap to change photo',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Main Form Card (White rounded card matching Screenshot 2)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // First Name & Last Name (Row)
                        Row(
                          children: [
                            Expanded(
                              child: _buildFormField(
                                icon: Icons.person_outline_rounded,
                                label: 'First name',
                                controller: first,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildFormField(
                                icon: Icons.person_outline_rounded,
                                label: 'Last name',
                                controller: last,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Phone Number
                        _buildFormField(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          controller: phone,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),

                        // Gender Dropdown
                        _buildLabel(Icons.transgender_rounded, 'Gender'),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBF7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderWarm),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: ['Female', 'Male', 'Non-binary', 'Prefer not to say'].contains(gender.text)
                                  ? gender.text
                                  : 'Female',
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted),
                              style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14.5),
                              items: const [
                                DropdownMenuItem(value: 'Female', child: Text('Female')),
                                DropdownMenuItem(value: 'Male', child: Text('Male')),
                                DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
                                DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
                              ],
                              onChanged: (v) => setState(() => gender.text = v ?? 'Female'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Hobbies
                        _buildFormField(
                          icon: Icons.favorite_border_rounded,
                          label: 'Hobbies',
                          controller: hobbies,
                          hint: 'e.g. Reading, Mindfulness, Yoga',
                        ),
                        const SizedBox(height: 14),

                        // Professional Title
                        _buildFormField(
                          icon: Icons.work_outline_rounded,
                          label: 'Professional title',
                          controller: title,
                          hint: 'e.g. Principal Empathy & Life Coach',
                        ),
                        const SizedBox(height: 14),

                        // Bio
                        _buildFormField(
                          icon: Icons.description_outlined,
                          label: 'Bio',
                          controller: bio,
                          minLines: 3,
                          maxLines: 5,
                        ),
                        const SizedBox(height: 14),

                        // Experience Years
                        _buildFormField(
                          icon: Icons.star_outline_rounded,
                          label: 'Experience years',
                          controller: experience,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 2: Services & Pricing matching Screenshot 2
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
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
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: softPeach,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                              ),
                              child: const Center(
                                child: Icon(Icons.monetization_on_rounded, color: primaryOrange, size: 17),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Services & pricing',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Consultation Type Label & Dropdown
                        const Text(
                          'Consultation type',
                          style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBF7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderWarm),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: consultationType,
                              isExpanded: true,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted),
                              style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14.5),
                              items: const [
                                DropdownMenuItem(value: 'BOTH', child: Text('Audio + video')),
                                DropdownMenuItem(value: 'AUDIO', child: Text('Audio only')),
                                DropdownMenuItem(value: 'VIDEO', child: Text('Video only')),
                              ],
                              onChanged: (v) => setState(() => consultationType = v ?? 'BOTH'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Rate Inputs Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildFormField(
                                icon: Icons.call_outlined,
                                label: 'Audio (₹/min)',
                                controller: audio,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildFormField(
                                icon: Icons.videocam_outlined,
                                label: 'Video (₹/min)',
                                controller: video,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildFormField(
                                icon: Icons.chat_bubble_outline_rounded,
                                label: 'Chat (₹/min)',
                                controller: chat,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (limits != null)
                          Text(
                            'Platform limits (${_isInternational ? 'International' : 'Domestic'}): Audio ₹${_limit('minAudioRatePerMinute', 5).toStringAsFixed(0)}–₹${_limit('maxAudioRatePerMinute', 50).toStringAsFixed(0)} • Video ₹${_limit('minVideoRatePerMinute', 10).toStringAsFixed(0)}–₹${_limit('maxVideoRatePerMinute', 100).toStringAsFixed(0)} • Chat ₹${_limit('minChatRatePerMinute', 2).toStringAsFixed(0)}–₹${_limit('maxChatRatePerMinute', 30).toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11, color: textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 3: Channel Availability matching Screenshot 2
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
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
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: softPeach,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                              ),
                              child: const Center(
                                child: Icon(Icons.tune_rounded, color: primaryOrange, size: 17),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Channel Availability',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: textDark,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Choose which communication channels callers can reach you on.',
                          style: TextStyle(fontSize: 12, color: textMuted),
                        ),
                        const SizedBox(height: 8),
                        _buildSwitchRow(
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          title: 'Private Chat',
                          subtitle: 'Text messaging with callers',
                          value: chatAvailable,
                          onChanged: (v) => setState(() => chatAvailable = v),
                        ),
                        const Divider(height: 16, color: borderWarm),
                        _buildSwitchRow(
                          icon: Icons.call_outlined,
                          iconColor: const Color(0xFF10B981),
                          title: 'Voice / Audio Call',
                          subtitle: 'Live 1-on-1 audio calling',
                          value: audioAvailable,
                          onChanged: (v) => setState(() => audioAvailable = v),
                        ),
                        const Divider(height: 16, color: borderWarm),
                        _buildSwitchRow(
                          icon: Icons.videocam_outlined,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'Video Call',
                          subtitle: 'High-definition video sessions',
                          value: videoAvailable,
                          onChanged: (v) => setState(() => videoAvailable = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 4: Categories & Languages Selection
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Listening Topics & Categories',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textDark),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Select categories where you can guide callers:',
                          style: TextStyle(fontSize: 12, color: textMuted),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allCategories.map((c) {
                            final id = '${c['id'] ?? ''}';
                            final name = '${c['name'] ?? id}';
                            final sel = selectedCategoryIds.contains(id);
                            return FilterChip(
                              label: Text(name),
                              selected: sel,
                              selectedColor: softPeach,
                              checkmarkColor: primaryOrange,
                              labelStyle: TextStyle(
                                color: sel ? primaryOrange : textDark,
                                fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                              ),
                              side: BorderSide(color: sel ? primaryOrange : borderWarm),
                              backgroundColor: Colors.white,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    selectedCategoryIds.add(id);
                                  } else {
                                    selectedCategoryIds.remove(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Languages Spoken',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textDark),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allLanguages.map((l) {
                            final code = '${l['code'] ?? ''}';
                            final name = '${l['name'] ?? code}';
                            final sel = selectedLanguageCodes.contains(code);
                            return FilterChip(
                              label: Text(name),
                              selected: sel,
                              selectedColor: softPeach,
                              checkmarkColor: primaryOrange,
                              labelStyle: TextStyle(
                                color: sel ? primaryOrange : textDark,
                                fontWeight: sel ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                              ),
                              side: BorderSide(color: sel ? primaryOrange : borderWarm),
                              backgroundColor: Colors.white,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    selectedLanguageCodes.add(code);
                                  } else {
                                    selectedLanguageCodes.remove(code);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Save Button
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [primaryOrange, secondaryOrange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: busy ? null : _save,
                        child: Center(
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Save Profile & Rates',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: primaryOrange),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(icon, label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.normal),
            filled: true,
            fillColor: const Color(0xFFFFFBF7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              borderSide: const BorderSide(color: primaryOrange, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: primaryOrange,
        ),
      ],
    );
  }
}
