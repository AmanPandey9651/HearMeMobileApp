import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

class AnonymousProfileScreen extends StatefulWidget {
  const AnonymousProfileScreen({super.key});

  @override
  State<AnonymousProfileScreen> createState() => _AnonymousProfileScreenState();
}

class _AnonymousProfileScreenState extends State<AnonymousProfileScreen> {
  AnonymousProfileModel? profile;
  bool loading = true;
  bool saving = false;
  final TextEditingController _nicknameCtrl = TextEditingController();
  final TextEditingController _bioCtrl = TextEditingController();

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color secondaryOrange = AppTheme.secondaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await context.read<AppController>().api.anonymousProfile();
      if (mounted) {
        setState(() {
          profile = p;
          _nicknameCtrl.text = p.nickname;
          _bioCtrl.text = p.bio ?? 'Looking for a peaceful listening ear';
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final updated = await context.read<AppController>().api.updateAnonymousProfile({
        'nickname': _nicknameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
      });
      if (mounted) {
        setState(() {
          profile = updated;
          saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anonymous profile saved successfully.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showError(context, e);
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uploading avatar…'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      final data = await context.read<AppController>().api.uploadAvatar(File(picked.path));
      final url = '${data['avatarUrl'] ?? data['secureUrl'] ?? data['url'] ?? ''}';
      if (url.isNotEmpty) {
        final updated = await context.read<AppController>().api.updateAnonymousProfile({'avatarUrl': url});
        if (mounted) {
          setState(() => profile = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Avatar updated successfully.'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _regenerateNickname() async {
    try {
      final updated = await context.read<AppController>().api.regenerateNickname();
      if (mounted) {
        setState(() {
          profile = updated;
          _nicknameCtrl.text = updated.nickname;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated nickname: ${updated.nickname}'),
            backgroundColor: primaryOrange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _showEditNicknameModal() {
    final ctrl = TextEditingController(text: _nicknameCtrl.text);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Edit Anonymous Nickname',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is the identity visible to listeners during calls and messages.',
              style: TextStyle(fontSize: 12.5, color: textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
              decoration: const InputDecoration(
                labelText: 'Anonymous ID',
                prefixIcon: Icon(Icons.shield_outlined, color: primaryOrange, size: 20),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  final text = ctrl.text.trim();
                  if (text.isNotEmpty) {
                    setState(() => _nicknameCtrl.text = text);
                  }
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Update Nickname', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBioModal() {
    final ctrl = TextEditingController(text: _bioCtrl.text);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'About You',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share what you are feeling or what kind of listening ear you need.',
              style: TextStyle(fontSize: 12.5, color: textMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(fontWeight: FontWeight.w600, color: textDark),
              decoration: const InputDecoration(
                hintText: 'Looking for a peaceful listening ear…',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  final text = ctrl.text.trim();
                  setState(() => _bioCtrl.text = text.isEmpty ? 'Looking for a peaceful listening ear' : text);
                  Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Update About You', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    if (loading) {
      return const Scaffold(
        backgroundColor: bgCream,
        body: Center(child: CircularProgressIndicator(color: primaryOrange)),
      );
    }

    final nickname = _nicknameCtrl.text.isNotEmpty ? _nicknameCtrl.text : (profile?.nickname ?? 'CosyCedar_7631');
    final bioText = _bioCtrl.text.isNotEmpty ? _bioCtrl.text : 'Looking for a peaceful listening ear';
    final avatarUrl = profile?.avatarUrl;

    return Scaffold(
      backgroundColor: bgCream,
      appBar: canPop
          ? AppBar(
              backgroundColor: bgCream,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'Anonymous Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textDark),
              ),
            )
          : null,
      body: Stack(
        children: [
          // Background soft organic blob shapes matching screenshot 2
          Positioned(
            top: -30,
            left: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: softPeach.withValues(alpha: 0.6),
              ),
            ),
          ),
          Positioned(
            top: 140,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFECE5).withValues(alpha: 0.5),
              ),
            ),
          ),

          // Main scrollable content
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                const SizedBox(height: 10),

                // 1. Large Circular Avatar with Camera Badge
                Center(
                  child: GestureDetector(
                    onTap: _pickAndUploadAvatar,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: softPeach,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? buildAvatarImage(
                                    avatarUrl,
                                    width: 104,
                                    height: 104,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person_rounded,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.person_rounded,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                          ),
                        ),

                        // Little orange camera button badge
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [primaryOrange, secondaryOrange],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryOrange.withValues(alpha: 0.35),
                                  blurRadius: 6,
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
                  ),
                ),

                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    'Tap to upload or change',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. Anonymous ID Card matching screenshot
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderWarm),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: softPeach,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield_outlined, color: primaryOrange, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          onTap: _showEditNicknameModal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Anonymous ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                nickname,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: primaryOrange, size: 20),
                        tooltip: 'Copy Anonymous ID',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: nickname));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied "$nickname" to clipboard.'),
                              backgroundColor: primaryOrange,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 3. About You Card matching screenshot
                InkWell(
                  onTap: _showEditBioModal,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: softPeach,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.graphic_eq_rounded, color: primaryOrange, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'About you',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                bioText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: primaryOrange, size: 22),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // 4. Dashed Orange Button: "Generate a new nickname"
                _DashedBorderButton(
                  onTap: _regenerateNickname,
                  icon: Icons.add,
                  label: 'Generate a new nickname',
                ),

                const SizedBox(height: 18),

                // 5. Bright Orange Gradient Button: "Save Profile"
                Container(
                  width: double.infinity,
                  height: 50,
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
                      onTap: saving ? null : _saveProfile,
                      child: Center(
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Save Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 6. Centered Footer Text matching screenshot
                const Center(
                  child: Text(
                    'Calls made are 100% anonymous and private.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF9CA3AF),
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
}

class _DashedBorderButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  const _DashedBorderButton({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const primaryOrange = AppTheme.primaryOrange;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primaryOrange,
            width: 1.2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: primaryOrange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, color: Colors.white, size: 13),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: primaryOrange,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
