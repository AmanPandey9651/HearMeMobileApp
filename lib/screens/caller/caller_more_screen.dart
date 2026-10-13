import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../widgets/sign_out_card.dart';
import '../common/how_it_works_screen.dart';
import '../common/notifications_screen.dart';
import '../common/safety_support_screen.dart';
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

          const SizedBox(height: 18),

          // 4. Luxury Sign Out Card
          const BeautifulSignOutCard(
            subtitle: 'End caller session & switch account',
          ),
        ],
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
  final VoidCallback onTap;

  const _MenuItemTile({
    required this.icon,
    required this.title,
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
                const Icon(Icons.chevron_right_rounded, color: AppTheme.primaryOrange, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
