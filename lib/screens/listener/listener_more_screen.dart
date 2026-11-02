import '../../services/app_lock_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../main.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sign_out_card.dart';
import '../common/how_it_works_screen.dart';
import '../common/notifications_screen.dart';
import '../common/safety_support_screen.dart';
import '../common/legal_policy_screen.dart';
import 'listener_dashboard_screen.dart';
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
  WalletModel? wallet;
  List<InstantSessionModel> sessions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final api = context.read<AppController>().api;
      final results = await Future.wait<dynamic>([
        api.myExpertProfile(),
        api.wallet(),
        api.listenerHistory(),
      ]);
      if (mounted) {
        setState(() {
          liveProfile = results[0] as Map<String, dynamic>?;
          wallet = results[1] as WalletModel?;
          sessions = results[2] as List<InstantSessionModel>;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final user = app.user;
    final expert = liveProfile ?? app.expertProfile;

    final displayName = user?.fullName.trim().isNotEmpty == true
        ? user!.fullName.trim()
        : ('${expert?['name'] ?? expert?['displayName'] ?? expert?['fullName'] ?? 'Verified Listener'}'.trim());
    final email = user?.email.isNotEmpty == true
        ? user!.email
        : '${expert?['email'] ?? 'listener@talkstrangers.com'}';
    final avatarUrl = expert?['avatarUrl']?.toString() ?? user?.avatarUrl;
    const role = 'VERIFIED LISTENER';

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

    final String presenceLabel = isBusy
        ? 'In a Consultation'
        : (isOnline ? 'Available for Calls' : 'Currently Offline');

    // Rates calculation
    final ratePerMin = (expert?['ratePerMinute'] as num?)?.toDouble() ?? 39.5;
    final videoRatePerMin = (expert?['videoRatePerMinute'] as num?)?.toDouble() ?? (ratePerMin * 1.5);
    final chatRatePerMin = (expert?['chatRatePerMinute'] as num?)?.toDouble() ?? (ratePerMin * 0.6);
    final netShareAudio = (ratePerMin * 0.50).round();
    final netShareVideo = (videoRatePerMin * 0.50).round();
    final netShareChat = (chatRatePerMin * 0.50).round();

    // Wallet & Gifts
    final walletBalance = wallet?.formattedBalance ?? '₹0.00';
    final totalGifts = sessions.fold<double>(0.0, (acc, s) => acc + s.giftEarnings);

    // Reviews & Ratings
    final rawReviews = (expert?['reviewCount'] ?? expert?['ratingCount'] as num?)?.toInt() ?? 0;
    final rawRating = (expert?['ratingAvg'] as num?)?.toDouble() ?? 0.0;
    final hasRatings = rawReviews > 0 && rawRating > 0;
    final ratingAvg = hasRatings ? rawRating : 4.8;
    final ratingSub = rawReviews == 0
        ? 'No caller reviews yet'
        : '⭐ ${ratingAvg.toStringAsFixed(1)} • Across $rawReviews caller ${rawReviews == 1 ? "review" : "reviews"}';

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
              backgroundColor: Colors.white,
              onRefresh: _fetchData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
                children: [
                  // Page Title Header
                  const Text(
                    'More',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Consultation rates, reviews, peers & preferences',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. Profile Hero Banner Card
                  Container(
                    padding: const EdgeInsets.all(16),
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
                          blurRadius: 12,
                          offset: const Offset(0, 3),
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
                                  width: 64,
                                  height: 64,
                                  child: buildAvatarImage(
                                    avatarUrl,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 64,
                                      height: 64,
                                      color: primaryOrange,
                                      child: Center(
                                        child: Text(
                                          displayName.isNotEmpty
                                              ? displayName.substring(0, 1).toUpperCase()
                                              : 'L',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 1,
                              right: 1,
                              child: Container(
                                width: 14,
                                height: 14,
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
                        const SizedBox(width: 14),

                        // User Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 17,
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
                                  fontSize: 12,
                                  color: textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFECE5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: primaryOrange.withValues(alpha: 0.25),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: const Text(
                                      role,
                                      style: TextStyle(
                                        color: primaryOrange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: presenceColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      presenceLabel,
                                      style: TextStyle(
                                        color: presenceColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),



                  // 2. Consultation Rates Card (Relocated from homepage)
                  Container(
                    padding: const EdgeInsets.all(16),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: softPeach,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.price_change_outlined, color: primaryOrange, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Consultation Rates',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: textDark,
                                      ),
                                    ),
                                    Text(
                                      '50% net listener share credited',
                                      style: TextStyle(fontSize: 11, color: textMuted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            InkWell(
                              onTap: () {
                                if (widget.onNavigateTab != null) {
                                  widget.onNavigateTab!(3); // Switch to Profile
                                } else {
                                  final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                                  nav.push(MaterialPageRoute(builder: (_) => const ListenerProfileScreen()));
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4EE),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Edit',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: primaryOrange),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_right_rounded, size: 14, color: primaryOrange),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // 3 Rate Pillars
                        Row(
                          children: [
                            // Audio Call Rate
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF5EE),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderWarm),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.call_rounded, color: primaryOrange, size: 18),
                                    const SizedBox(height: 4),
                                    const Text('Voice', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${ratePerMin.toStringAsFixed(1)}/m',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textDark),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8FDF3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '₹$netShareAudio net',
                                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Video Call Rate
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF5EE),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderWarm),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.videocam_rounded, color: Color(0xFF8B5CF6), size: 18),
                                    const SizedBox(height: 4),
                                    const Text('Video', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${videoRatePerMin.toStringAsFixed(1)}/m',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textDark),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8FDF3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '₹$netShareVideo net',
                                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Text Chat Rate
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF5EE),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderWarm),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.chat_bubble_rounded, color: Color(0xFF2563EB), size: 18),
                                    const SizedBox(height: 4),
                                    const Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${chatRatePerMin.toStringAsFixed(1)}/m',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: textDark),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8FDF3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '₹$netShareChat net',
                                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Tap for full breakdown
                        InkWell(
                          onTap: () {
                            showConsultationRatesSheet(
                              context: context,
                              audioRate: ratePerMin,
                              videoRate: videoRatePerMin,
                              chatRate: chatRatePerMin,
                              audioNet: netShareAudio,
                              videoNet: netShareVideo,
                              chatNet: netShareChat,
                              onEditRates: () {
                                Navigator.of(context).pop();
                                widget.onNavigateTab?.call(3);
                              },
                            );
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            child: const Text(
                              'View full pricing breakdown & share policy ›',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryOrange),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Earnings & Gifts Quick Card (Relocated from homepage)
                  Container(
                    padding: const EdgeInsets.all(16),
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
                    child: Row(
                      children: [
                        // Left: Available Balance & UPI Payout
                        Expanded(
                          child: InkWell(
                            onTap: () => widget.onNavigateTab?.call(2), // Tab 2 Earnings
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet_outlined, size: 16, color: primaryOrange),
                                      SizedBox(width: 5),
                                      Text('Available Payout', style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    walletBalance,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFEA580C)),
                                  ),
                                  const SizedBox(height: 4),
                                  const Row(
                                    children: [
                                      Text('UPI Payouts', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primaryOrange)),
                                      SizedBox(width: 2),
                                      Icon(Icons.chevron_right_rounded, size: 14, color: primaryOrange),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Container(width: 1, height: 48, color: borderWarm),
                        const SizedBox(width: 14),

                        // Right: Virtual Gifts & Tips
                        Expanded(
                          child: InkWell(
                            onTap: () => widget.onNavigateTab?.call(2), // Tab 2 Earnings
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.card_giftcard_rounded, size: 16, color: Color(0xFFEC4899)),
                                      SizedBox(width: 5),
                                      Text('Caller Gifts', style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₹${totalGifts.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textDark),
                                  ),
                                  const SizedBox(height: 4),
                                  const Row(
                                    children: [
                                      Text('Gift History', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEC4899))),
                                      SizedBox(width: 2),
                                      Icon(Icons.chevron_right_rounded, size: 14, color: Color(0xFFEC4899)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. Community & Reputation Card (Reviews & Live Peers)
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
                        _MenuRowItemWithSubtitle(
                          icon: Icons.star_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          iconBgColor: const Color(0xFFFEF3C7),
                          title: 'Caller Reviews & Ratings',
                          subtitle: ratingSub,
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(MaterialPageRoute(builder: (_) => const ListenerReviewsScreen()));
                          },
                        ),
                        const Divider(height: 1, color: borderWarm, indent: 64),
                        _MenuRowItemWithSubtitle(
                          icon: Icons.people_alt_rounded,
                          iconColor: const Color(0xFF0D9488),
                          iconBgColor: const Color(0xFFCCFBF1),
                          title: 'Other Listeners (Live Status)',
                          subtitle: 'See who is online, offline or busy',
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(MaterialPageRoute(builder: (_) => const ListenerPeersScreen()));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. Account & Preferences Card
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
                          title: 'Profile Settings',
                          onTap: () {
                            if (widget.onNavigateTab != null) {
                              widget.onNavigateTab!(3); // Switch to Profile Tab
                            } else {
                              final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                              nav.push(
                                MaterialPageRoute(builder: (_) => const ListenerProfileScreen()),
                              );
                            }
                          },
                        ),
                        const Divider(height: 1, color: borderWarm, indent: 64),
                        Consumer<AppLockService>(
                          builder: (_, lock, __) => _MenuRowItem(
                            icon: Icons.lock_outline_rounded,
                            title: 'App Lock & Security PIN',
                            trailingBadge: lock.isLockEnabled ? 'Active' : null,
                            trailingBadgeColor: const Color(0xFF16A34A),
                            onTap: () => _showAppLockConfigDialog(context),
                          ),
                        ),
                        const Divider(height: 1, color: borderWarm, indent: 64),
                        _MenuRowItem(
                          icon: Icons.notifications_none_rounded,
                          title: 'Notifications',
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(
                              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1, color: borderWarm, indent: 64),
                        _MenuRowItem(
                          icon: Icons.shield_outlined,
                          title: 'Safety, blocked users & support',
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(
                              MaterialPageRoute(builder: (_) => const SafetySupportScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1, color: borderWarm, indent: 64),
                        _MenuRowItem(
                          icon: Icons.info_outline_rounded,
                          title: 'How it works',
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(
                              MaterialPageRoute(builder: (_) => const HowItWorksScreen()),
                            );
                          },
                        ),
                        const Divider(height: 1, thickness: 1, color: borderWarm, indent: 64),
                        _MenuRowItem(
                          icon: Icons.policy_outlined,
                          title: 'Privacy Policy & Terms',
                          onTap: () {
                            final nav = TalkStrangersApp.navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
                            nav.push(
                              MaterialPageRoute(builder: (_) => const LegalPolicyScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 6. Luxury Sign out Card
                  const BeautifulSignOutCard(
                    subtitle: 'End listener session & take a break',
                  ),
                ],
              ),
            ),
          ),
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
                        child: const Icon(Icons.shield_rounded, color: primaryOrange, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Lock & Privacy',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: textDark),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Protect your earnings & consultations',
                              style: TextStyle(fontSize: 12, color: textMuted),
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
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: textDark),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Locks FeelBack on app switch',
                                style: TextStyle(fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          activeTrackColor: primaryOrange,
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
                      color: textDark,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Set 4-Digit Security PIN',
                      labelStyle: const TextStyle(fontSize: 13, color: textMuted, letterSpacing: 0),
                      hintText: '••••',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: primaryOrange, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: textMuted,
                          size: 20,
                        ),
                        onPressed: () => setLocalState(() => obscurePin = !obscurePin),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryOrange, width: 1.8)),
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
                            side: const BorderSide(color: borderWarm),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: textMuted, fontWeight: FontWeight.w700)),
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
                                color: primaryOrange.withValues(alpha: 0.3),
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
        border: Border.all(color: borderWarm),
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
                    color: softPeach,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFCDFD5),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      color: iconColor ?? primaryOrange,
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
                      color: textDark,
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
  final String? trailingBadge;
  final Color? trailingBadgeColor;

  const _MenuRowItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingBadge,
    this.trailingBadgeColor,
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
                  color: softPeach,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFCDFD5),
                    width: 0.8,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: primaryOrange,
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
                    color: textDark,
                  ),
                ),
              ),
              if (trailingBadge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (trailingBadgeColor ?? primaryOrange).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    trailingBadge!,
                    style: TextStyle(
                      color: trailingBadgeColor ?? primaryOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
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

class _MenuRowItemWithSubtitle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuRowItemWithSubtitle({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
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
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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
