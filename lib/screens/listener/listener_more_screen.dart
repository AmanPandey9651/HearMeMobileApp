import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../widgets/common_widgets.dart';
import '../common/how_it_works_screen.dart';
import '../common/notifications_screen.dart';
import '../common/safety_support_screen.dart';
import 'listener_peers_screen.dart';
import 'listener_profile_screen.dart';
import 'listener_reviews_screen.dart';

const Color bgCream = Color(0xFFFAF5EE);
const Color borderWarm = Color(0xFFF1E6D8);
const Color primaryOrange = Color(0xFFF95B3D);
const Color secondaryOrange = Color(0xFFFF7A45);
const Color softPeach = Color(0xFFFFECE5);
const Color textDark = Color(0xFF111827);
const Color textMuted = Color(0xFF6B7280);

class ListenerMoreScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;
  const ListenerMoreScreen({super.key, this.onNavigateTab});

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  State<ListenerMoreScreen> createState() => _ListenerMoreScreenState();
}

class _ListenerMoreScreenState extends State<ListenerMoreScreen> {
  Map<String, dynamic>? liveProfile;

  @override
  void initState() {
    super.initState();
    _fetchLivePresence();
  }

  Future<void> _fetchLivePresence() async {
    try {
      final p = await context.read<AppController>().api.myExpertProfile();
      if (mounted) {
        setState(() => liveProfile = p);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final user = app.user;
    final expert = liveProfile ?? app.expertProfile;

    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : ('${expert?['name'] ?? 'Verified Listener'}'.trim());
    final email = user?.email.isNotEmpty == true
        ? user!.email
        : '${expert?['email'] ?? 'listener@talkstrangers.com'}';
    final avatarUrl = expert?['avatarUrl']?.toString() ?? user?.avatarUrl;
    const role = 'LISTENER';

    final presence = (expert?['presenceStatus'] ?? expert?['presence'] ?? 'OFFLINE').toString().toUpperCase();
    final activeSessionType = expert?['activeSessionType']?.toString();
    final hasActiveCall = activeSessionType != null && activeSessionType.isNotEmpty;
    final isBusy = presence.contains('BUSY') || hasActiveCall;
    final isOnline = (presence == 'ONLINE' || presence.contains('AVAILABLE')) && !isBusy;

    final Color presenceColor = isBusy
        ? const Color(0xFFEF4444) // Busy: red dot
        : (isOnline
            ? const Color(0xFF10B981) // Online: green dot
            : const Color(0xFF9CA3AF)); // Offline: grey dot

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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                // Page Title Header
                const Text(
                  'More',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 18),

                // Card 1: Caller reviews
                _MenuItemCard(
                  icon: Icons.rate_review_rounded,
                  title: 'Caller reviews',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ListenerReviewsScreen()),
                  ),
                ),
                const SizedBox(height: 14),

                // Card 2: User Profile Banner Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFF2EB), Color(0xFFFFE6D8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: const Color(0xFFFCDFD5), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: primaryOrange.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Avatar with online beacon dot
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: SizedBox(
                                width: 72,
                                height: 72,
                                child: buildAvatarImage(
                                  avatarUrl,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 72,
                                    height: 72,
                                    color: primaryOrange,
                                    child: Center(
                                      child: Text(
                                        displayName.isNotEmpty
                                            ? displayName.substring(0, 1).toUpperCase()
                                            : 'L',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 15,
                              height: 15,
                              decoration: BoxDecoration(
                                color: presenceColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: presenceColor.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),

                      // User Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textDark,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFECE5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: primaryOrange.withValues(alpha: 0.25),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                role,
                                style: const TextStyle(
                                  color: primaryOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 3: Settings Menu Card (4 items with dividers)
                Container(
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
                    children: [
                      _MenuRowItem(
                        icon: Icons.person_outline_rounded,
                        title: 'Profile',
                        onTap: () {
                          if (widget.onNavigateTab != null) {
                            widget.onNavigateTab!(3); // Switch to Profile Tab
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ListenerProfileScreen()),
                            );
                          }
                        },
                      ),
                      const Divider(height: 1, color: borderWarm, indent: 64),
                      _MenuRowItem(
                        icon: Icons.notifications_none_rounded,
                        title: 'Notifications',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        ),
                      ),
                      const Divider(height: 1, color: borderWarm, indent: 64),
                      _MenuRowItem(
                        icon: Icons.shield_outlined,
                        title: 'Safety, blocked users & support',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SafetySupportScreen()),
                        ),
                      ),
                      const Divider(height: 1, color: borderWarm, indent: 64),
                      _MenuRowItem(
                        icon: Icons.info_outline_rounded,
                        title: 'How it works',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HowItWorksScreen()),
                        ),
                      ),
                      const Divider(height: 1, color: borderWarm, indent: 64),
                      _MenuRowItem(
                        icon: Icons.people_outline_rounded,
                        title: 'Other Listeners (Live Status)',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ListenerPeersScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Card 4: Sign out Card
                _MenuItemCard(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  iconColor: primaryOrange,
                  onTap: () async {
                    final shouldLogout = await confirm(
                      context,
                      'Sign out',
                      'Are you sure you want to sign out of your listener account?',
                    );
                    if (shouldLogout) {
                      await app.logout();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;

  const _MenuItemCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ListenerMoreScreen.borderWarm),
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
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ListenerMoreScreen.softPeach,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFCDFD5),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: iconColor ?? ListenerMoreScreen.primaryOrange,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ListenerMoreScreen.textDark,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRowItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuRowItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: ListenerMoreScreen.softPeach,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFCDFD5),
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: ListenerMoreScreen.primaryOrange,
                    size: 19,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ListenerMoreScreen.textDark,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF9CA3AF),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
