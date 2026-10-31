import '../common/refer_and_earn_screen.dart';
import '../../widgets/share_app_sheet.dart';
import '../../services/app_lock_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../widgets/sign_out_card.dart';
import '../common/how_it_works_screen.dart';
import '../common/notifications_screen.dart';
import '../common/safety_support_screen.dart';
import '../common/legal_policy_screen.dart';
import '../../main.dart';
import 'anonymous_profile_screen.dart';
import 'followed_listeners_screen.dart';

class CallerMoreScreen extends StatelessWidget {
  const CallerMoreScreen({super.key});

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color secondaryOrange = AppTheme.secondaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final user = app.user;
    final fullName = (user?.fullName.isNotEmpty == true) ? user!.fullName : 'Aman Pandey';
    final email = user?.email.isNotEmpty == true ? user!.email : 'amanpandey221503@gmail.com';
    final role = (user?.role.isNotEmpty == true ? user!.role : 'CUSTOMER').toUpperCase();

    return Scaffold(
      backgroundColor: bgCream,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
        children: [
          // 1. Favourite Listeners Card matching Screenshot 2 (Right)
          _MenuActionCard(
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const FollowedListenersScreen()));
            },
            leading: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: softPeach,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded, color: primaryOrange, size: 22),
            ),
            titleWidget: const Text(
              'Favourite listeners',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: primaryOrange,
              ),
            ),
            subtitle: 'Listeners you follow and online alerts',
            showChevron: true,
          ),

          const SizedBox(height: 14),

          // 2. Customer Profile Card matching Screenshot 2 (Right)
          _MenuActionCard(
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const AnonymousProfileScreen()));
            },
            leading: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: softPeach,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
            ),
            titleWidget: Text(
              fullName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textDark,
              ),
            ),
            subtitleWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(fontSize: 12.5, color: textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: softPeach,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCDFD5)),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: primaryOrange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            showChevron: true,
          ),

          const SizedBox(height: 18),

          // 3. Settings Menu Cards matching Screenshot 2 (Right)
          _MenuItemTile(
            icon: Icons.manage_accounts_outlined,
            title: 'Profile',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const AnonymousProfileScreen()));
            },
          ),
          const SizedBox(height: 10),

          // Refer & Earn
          _MenuItemTile(
            icon: Icons.card_giftcard_rounded,
            title: 'Refer & Earn',
            trailingBadge: 'Earn ₹20',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const ReferAndEarnScreen()));
            },
          ),
          const SizedBox(height: 10),

          // Share App
          _MenuItemTile(
            icon: Icons.share_rounded,
            title: 'Share App with Friends',
            onTap: () => showShareAppSheet(context),
          ),
          const SizedBox(height: 10),

          // App Lock & Security PIN
          _MenuItemTile(
            icon: Icons.lock_outline_rounded,
            title: 'App Lock & Security PIN',
            onTap: () => _showAppLockConfigDialog(context),
          ),
          const SizedBox(height: 10),
          _MenuItemTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            },
          ),
          const SizedBox(height: 10),

          _MenuItemTile(
            icon: Icons.shield_outlined,
            title: 'Safety, blocked users & support',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const SafetySupportScreen()));
            },
          ),
          const SizedBox(height: 10),

          _MenuItemTile(
            icon: Icons.info_outline_rounded,
            title: 'How it works',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const HowItWorksScreen()));
            },
          ),
          const SizedBox(height: 10),

          _MenuItemTile(
            icon: Icons.policy_outlined,
            title: 'Privacy Policy & Terms of Service',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const LegalPolicyScreen()));
            },
          ),

          const SizedBox(height: 18),

          // 4. Luxury Sign Out Card
          const BeautifulSignOutCard(
            subtitle: 'End caller session & switch account',
          ),
        ],
      ),
    );
  }

  void _showAppLockConfigDialog(BuildContext context) {
    final lockService = context.read<AppLockService>();
    final pinController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final isEnabled = lockService.isLockEnabled;
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: AppTheme.primaryOrange, size: 24),
                SizedBox(width: 10),
                Text('App Lock & Privacy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textDark)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: AppTheme.primaryOrange,
                  title: const Text('Require 4-digit PIN', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: const Text('Locks FeelBack whenever app goes to background', style: TextStyle(fontSize: 11.5)),
                  value: isEnabled,
                  onChanged: (val) async {
                    if (val) {
                      if (pinController.text.trim().length != 4) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a 4-digit PIN below first!')),
                        );
                        return;
                      }
                      await lockService.setPin(pinController.text.trim());
                    } else {
                      await lockService.setLockEnabled(false);
                    }
                    setLocalState(() {});
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.w800, fontSize: 16),
                  decoration: InputDecoration(
                    labelText: 'Set 4-Digit Security PIN',
                    hintText: '••••',
                    counterText: '',
                    filled: true,
                    fillColor: AppTheme.bgCream,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.borderWarm)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryOrange),
                onPressed: () async {
                  if (pinController.text.trim().length == 4) {
                    await lockService.setPin(pinController.text.trim());
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('4-Digit Security PIN saved successfully!')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN must be exactly 4 digits!')),
                    );
                  }
                },
                child: const Text('Save PIN', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

}

class _MenuActionCard extends StatelessWidget {
  final VoidCallback onTap;
  final Widget leading;
  final Widget titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final bool showChevron;

  const _MenuActionCard({
    required this.onTap,
    required this.leading,
    required this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderWarm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      titleWidget,
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                        ),
                      ],
                      if (subtitleWidget != null) subtitleWidget!,
                    ],
                  ),
                ),
                if (showChevron)
                  const Icon(Icons.chevron_right_rounded, color: AppTheme.primaryOrange, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItemTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingBadge;
  final VoidCallback onTap;

  const _MenuItemTile({
    required this.icon,
    required this.title,
    this.trailingBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderWarm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primaryOrange, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                if (trailingBadge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDBA74)),
                    ),
                    child: Text(
                      trailingBadge!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Icon(Icons.chevron_right_rounded, color: AppTheme.primaryOrange, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
