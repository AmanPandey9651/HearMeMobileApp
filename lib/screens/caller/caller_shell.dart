import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import 'anonymous_profile_screen.dart';
import 'caller_history_screen.dart';
import 'caller_home_screen.dart';
import 'caller_more_screen.dart';
import 'wallet_screen.dart';

class CallerShell extends StatefulWidget {
  const CallerShell({super.key});

  @override
  State<CallerShell> createState() => _CallerShellState();
}

class _CallerShellState extends State<CallerShell> {
  int index = 0;
  Timer? callbackPoll;
  Timer? navPoll;
  String? shownCallback;
  int unreadCount = 0;
  WalletModel? topWallet;

  // Curated theme colors for warm luxury light aesthetic
  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  final pages = const [
    CallerHomeScreen(),
    CallerHistoryScreen(),
    WalletScreen(),
    AnonymousProfileScreen(),
    CallerMoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    callbackPoll = Timer.periodic(const Duration(seconds: 3), (_) => _checkCallback());
    navPoll = Timer.periodic(const Duration(seconds: 20), (_) => _refreshNav());
    Future<void>.delayed(const Duration(milliseconds: 500), _refreshNav);
  }

  @override
  void dispose() {
    callbackPoll?.cancel();
    navPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshNav() async {
    try {
      final api = context.read<AppController>().api;
      final values = await Future.wait<dynamic>([api.unreadCount(), api.wallet()]);
      if (mounted) {
        setState(() {
          unreadCount = values[0] as int;
          topWallet = values[1] as WalletModel;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkCallback() async {
    try {
      final list = await context.read<AppController>().api.callerHistory();
      final matches = list.where((s) => s.reference.startsWith('CB-') && s.status == 'REQUESTED').toList();
      if (matches.isEmpty || !mounted) return;
      final s = matches.first;
      if (shownCallback == s.id) return;
      shownCallback = s.id;
      await _showCallback(s);
    } catch (_) {}
  }

  Future<void> _showCallback(InstantSessionModel s) async {
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderWarm),
        ),
        title: const Text('Listener is calling you back', style: TextStyle(color: textDark, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RemoteAvatar(url: s.listenerAvatarUrl, radius: 38, fallback: s.listenerName),
            const SizedBox(height: 10),
            Text(s.listenerName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
            const SizedBox(height: 4),
            Text(
              '${s.type.replaceAll('_', ' ')} • ₹${s.ratePerMinute.toStringAsFixed(0)}/min',
              style: const TextStyle(fontSize: 13, color: primaryOrange, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Decline', style: TextStyle(color: textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    try {
      if (yes == true) {
        final accepted = await context.read<AppController>().api.acceptSession(s.id);
        ActiveCallManager.instance.startCall(accepted, callerSide: true);
      } else {
        await context.read<AppController>().api.rejectSession(s.id, 'Caller declined callback');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    shownCallback = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: index == 0
            ? Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [primaryOrange, secondaryOrange],
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
                    child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textDark, letterSpacing: -0.4),
                      children: [
                        TextSpan(text: 'Hear'),
                        TextSpan(text: 'Me', style: TextStyle(color: primaryOrange)),
                      ],
                    ),
                  ),
                ],
              )
            : Text(
                ['HearMe', 'Sessions', 'Wallet', 'Anonymous Profile', 'More'][index],
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: textDark),
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              onTap: () => setState(() => index = 2),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: softPeach,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFCDFD5), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, size: 16, color: primaryOrange),
                    const SizedBox(width: 6),
                    Text(
                      topWallet?.formattedBalance ?? '₹0.00',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        color: primaryOrange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 10, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
              if (val == 'wallet') {
                setState(() => index = 2);
              } else if (val == 'history') {
                setState(() => index = 1);
              } else if (val == 'profile') {
                setState(() => index = 3);
              } else if (val == 'logout') {
                context.read<AppController>().logout();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'wallet',
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_rounded, size: 18, color: primaryOrange),
                    SizedBox(width: 10),
                    Text('My Wallet', style: TextStyle(color: textDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: textMuted),
                    SizedBox(width: 10),
                    Text('Session History', style: TextStyle(color: textDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 18, color: textMuted),
                    SizedBox(width: 10),
                    Text('My Profile', style: TextStyle(color: textDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: primaryOrange),
                    SizedBox(width: 10),
                    Text('Log Out', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: borderWarm, width: 1.0)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          backgroundColor: Colors.white,
          indicatorColor: softPeach,
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded, color: primaryOrange),
              label: 'Talk',
            ),
            const NavigationDestination(
              icon: Icon(Icons.history_rounded),
              selectedIcon: Icon(Icons.history_rounded, color: primaryOrange),
              label: 'History',
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded, color: primaryOrange),
              label: 'Wallet',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: primaryOrange),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                backgroundColor: const Color(0xFFEF4444),
                textColor: Colors.white,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                child: const Icon(Icons.more_horiz_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: unreadCount > 0,
                backgroundColor: const Color(0xFFEF4444),
                textColor: Colors.white,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                child: const Icon(Icons.more_horiz_rounded, color: primaryOrange),
              ),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
