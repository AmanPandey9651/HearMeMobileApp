import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';

class ListenerVerificationPendingScreen extends StatefulWidget {
  const ListenerVerificationPendingScreen({super.key});

  @override
  State<ListenerVerificationPendingScreen> createState() => _ListenerVerificationPendingScreenState();
}

class _ListenerVerificationPendingScreenState extends State<ListenerVerificationPendingScreen> {
  bool _isChecking = false;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final app = context.read<AppController>();
      await app.refreshUser();
      if (!mounted) return;

      if (app.isListenerVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Congratulations! Your profile has been verified! Welcome to FeelAgain.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your profile is still under review. We will contact you by email once approved!'),
            backgroundColor: Color(0xFF374151),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to reach verification server. Please check your internet connection.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _showSupportModal() {
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const Row(
              children: [
                Icon(Icons.headset_mic_rounded, color: primaryOrange, size: 22),
                SizedBox(width: 8),
                Text(
                  'Listener Onboarding Support',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Have questions about your verification or need to update your submitted credentials?',
              style: TextStyle(fontSize: 13.5, color: textMuted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderWarm),
              ),
              child: const Row(
                children: [
                  Icon(Icons.email_outlined, color: primaryOrange, size: 20),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Official Verification Desk', style: TextStyle(fontSize: 11, color: textMuted)),
                      Text(
                        'support@hearme.com',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Got It', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final user = app.user;
    final email = user?.email ?? 'your email';

    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 18,
        title: Image.asset(
          'assets/images/feelagain-splash.png',
          height: 36,
          fit: BoxFit.contain,
        ),
        actions: [
          // Sign Out Button
          TextButton.icon(
            onPressed: () => app.logout(),
            icon: const Icon(Icons.logout_rounded, size: 16, color: primaryOrange),
            label: const Text(
              'Log Out',
              style: TextStyle(
                color: primaryOrange,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            const SizedBox(height: 12),

            // 1. Centered Hero Verification Badge with Warm Glow
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer soft peach radial halo
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: softPeach,
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.15),
                          blurRadius: 24,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),

                  // Inner Gradient Circle with Icon
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [primaryOrange, secondaryOrange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.38),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mark_email_read_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),

                  // Sparkle Badge
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xFFF59E0B),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Status Badge Pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD97706),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Verification In Progress',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 3. Primary Title
            const Text(
              'Your Profile Has Been Sent for Verification',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: textDark,
                letterSpacing: -0.4,
                height: 1.25,
              ),
            ),

            const SizedBox(height: 10),

            // 4. Core User-Requested Message
            const Text(
              'You will be contacted through email once your listener account is approved by our team.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: textMuted,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 18),

            // 5. Registered Email Pill Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: softPeach,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mail_outline_rounded, color: primaryOrange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notification Email',
                          style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 6. Application Timeline Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderWarm),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Application Timeline',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Step 1: Application Submitted (Done)
                  _TimelineStep(
                    icon: Icons.check_circle_rounded,
                    iconColor: const Color(0xFF10B981),
                    iconBg: const Color(0xFFD1FAE5),
                    title: 'Application Submitted',
                    description: 'Your registration details, bio, and rates were received successfully.',
                    isLast: false,
                  ),

                  // Step 2: Quality & Safety Review (In Progress)
                  _TimelineStep(
                    icon: Icons.sync_rounded,
                    iconColor: primaryOrange,
                    iconBg: softPeach,
                    title: 'Safety & Empathy Vetting',
                    description: 'Our review team is currently evaluating your profile standards.',
                    isLast: false,
                  ),

                  // Step 3: Email Notification & Access (Pending)
                  const _TimelineStep(
                    icon: Icons.mark_email_unread_outlined,
                    iconColor: Color(0xFF94A3B8),
                    iconBg: Color(0xFFF1F5F9),
                    title: 'Approval Email & Dashboard Access',
                    description: 'You will receive an official approval email. Once approved, the listener dashboard opens automatically.',
                    isLast: true,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 7. Review Time Note
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: softPeach,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFCDFD5)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: primaryOrange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Reviews typically take 24–48 hours. Thank you for your patience and for dedicating your time to supporting others.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF7C2D12),
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 8. Primary Button: Check Verification Status
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _isChecking ? null : _checkStatus,
                icon: _isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: Text(
                  _isChecking ? 'Checking Verification…' : 'Check Verification Status',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 9. Secondary Support Action
            Center(
              child: TextButton.icon(
                onPressed: _showSupportModal,
                icon: const Icon(Icons.help_outline_rounded, size: 16, color: textMuted),
                label: const Text(
                  'Need assistance? Contact Support',
                  style: TextStyle(
                    fontSize: 13,
                    color: textMuted,
                    fontWeight: FontWeight.w600,
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

class _TimelineStep extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;
  final bool isLast;

  const _TimelineStep({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon and connecting vertical line
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 18),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      height: 1.35,
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
}
