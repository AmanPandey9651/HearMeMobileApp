import '../common/refer_and_earn_screen.dart';
import '../../widgets/share_app_sheet.dart';
import '../../services/app_lock_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../widgets/sign_out_card.dart';
import '../../widgets/delete_account_card.dart';
import '../common/how_it_works_screen.dart';
import '../common/chat_inbox_screen.dart';
import '../common/notifications_screen.dart';
import '../common/safety_support_screen.dart';
import '../common/legal_policy_screen.dart';
import '../../main.dart';
import 'anonymous_profile_screen.dart';
import 'followed_listeners_screen.dart';

class CallerMoreScreen extends StatefulWidget {
  const CallerMoreScreen({super.key});

  @override
  State<CallerMoreScreen> createState() => _CallerMoreScreenState();
}

class _CallerMoreScreenState extends State<CallerMoreScreen> {
  num? _customBonus;

  static const Color bgCream = AppTheme.bgCream;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    _fetchReferralBonus();
  }

  Future<void> _fetchReferralBonus() async {
    try {
      final app = context.read<AppController>();
      final summary = await app.api.getReferralSummary();
      final bonus = summary['potentialRewardPerReferral'];
      if (bonus != null && mounted) {
        final parsed = bonus is num ? bonus : num.tryParse(bonus.toString());
        if (parsed != null && parsed > 0) {
          setState(() => _customBonus = parsed);
        }
      }
    } catch (_) {}
  }

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
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chat Inbox',
            trailingBadge: 'Direct Messages',
            onTap: () {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              nav.push(MaterialPageRoute(builder: (_) => const ChatInboxScreen(isListener: false)));
            },
          ),
          const SizedBox(height: 10),
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
            trailingBadge: () {
              final amount = _customBonus ?? app.referralRewardAmount;
              final str = (amount.toInt() == amount) ? '${amount.toInt()}' : amount.toStringAsFixed(0);
              return 'Earn ₹$str';
            }(),
            onTap: () async {
              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
              await nav.push(MaterialPageRoute(builder: (_) => const ReferAndEarnScreen()));
              _fetchReferralBonus();
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

          const SizedBox(height: 12),

          // 5. Delete Account Card (Apple Guideline 5.1.1(v))
          const BeautifulDeleteAccountCard(),
        ],
      ),
    );
  }

  void _showAppLockConfigDialog(BuildContext context) {
    final lockService = context.read<AppLockService>();
    final pinController = TextEditingController();
    bool obscurePin = true;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          final isEnabled = lockService.isLockEnabled;
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with Badge
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0EC),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFED7AA), width: 1.2),
                        ),
                        child: const Icon(Icons.shield_rounded, color: AppTheme.primaryOrange, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Lock & Privacy',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppTheme.textDark),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Protect your chats and calls',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Switch Container
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF5EE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1E6D8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Require 4-Digit PIN',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppTheme.textDark),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Locks FeelBack on app switch',
                                style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          activeTrackColor: AppTheme.primaryOrange,
                          activeThumbColor: Colors.white,
                          onChanged: (val) async {
                            if (val) {
                              if (pinController.text.trim().length != 4) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter a 4-digit PIN below first!'),
                                    backgroundColor: Color(0xFFEF4444),
                                    behavior: SnackBarBehavior.floating,
                                  ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // PIN Input Field
                  TextField(
                    controller: pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: obscurePin,
                    style: const TextStyle(
                      letterSpacing: 8,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: AppTheme.textDark,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Set 4-Digit Security PIN',
                      labelStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted, letterSpacing: 0),
                      hintText: '••••',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppTheme.primaryOrange, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        onPressed: () => setLocalState(() => obscurePin = !obscurePin),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.borderWarm)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.borderWarm)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primaryOrange, width: 1.8)),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: const BorderSide(color: AppTheme.borderWarm),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6A00), Color(0xFFF95B3D)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryOrange.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () async {
                              if (pinController.text.trim().length == 4) {
                                await lockService.setPin(pinController.text.trim());
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, color: Colors.white),
                                          SizedBox(width: 10),
                                          Text('4-Digit Security PIN saved successfully!'),
                                        ],
                                      ),
                                      backgroundColor: Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('PIN must be exactly 4 digits!'),
                                    backgroundColor: Color(0xFFEF4444),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            child: const Text('Save PIN', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
