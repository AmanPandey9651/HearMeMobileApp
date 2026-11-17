import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/call_push_service.dart';
import 'package:feelback_ringtone/feelback_ringtone.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/incoming_call_overlay.dart';
import '../common/chat_inbox_screen.dart';
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
  int chatUnreadCount = 0;
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
    CallPushService.instance.onForegroundIncomingCall = _checkCallback;
    CallPushService.instance.onAlertNotificationReceived = _refreshNav;
  }

  @override
  void dispose() {
    if (CallPushService.instance.onForegroundIncomingCall == _checkCallback) {
      CallPushService.instance.onForegroundIncomingCall = null;
    }
    if (CallPushService.instance.onAlertNotificationReceived == _refreshNav) {
      CallPushService.instance.onAlertNotificationReceived = null;
    }
    callbackPoll?.cancel();
    navPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshNav() async {
    try {
      final api = context.read<AppController>().api;
      final values = await Future.wait<dynamic>([
        api.unreadCount(),
        api.wallet(),
        api.getInboxUnreadCount(),
      ]);
      if (mounted) {
        setState(() {
          unreadCount = values[0] as int;
          topWallet = values[1] as WalletModel;
          chatUnreadCount = values[2] as int;
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
      if (ActiveCallManager.instance.activeSession?.id == s.id) return;
      shownCallback = s.id;
      await _showCallback(s);
    } catch (_) {}
  }

  Future<void> _showCallback(InstantSessionModel s) async {
    CallPushService.instance.markSessionHandledInApp(s.id);
    try {
      final yes = await IncomingCallOverlay.show(context, s, isCallback: true);

      try {
        if (yes == true) {
          FeelBackRingtone.markAccepted(s.id, source: 'caller_shell._showCallback_accepted');
          final accepted = await context.read<AppController>().api.acceptSession(s.id);
          ActiveCallManager.instance.startCall(accepted, callerSide: true);
        } else {
          FeelBackRingtone.markTerminal(s.id, 'DECLINED', source: 'caller_shell._showCallback_declined');
          await context.read<AppController>().api.rejectSession(s.id, 'Caller declined callback');
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    } finally {
      if (!FeelBackRingtone.isCallGuarded(s.id)) {
        CallPushService.instance.clearSessionHandledInApp(s.id);
      }
      unawaited(CallPushService.instance.dismissCallNotification(s.id));
      shownCallback = s.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: bgCream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: index == 0
            ? Image.asset(
                app.headerLogoAsset,
                height: 27,
                fit: BoxFit.contain,
              )
            : Text(
                [app.activeBrandName, 'Sessions', 'Wallet', 'Anonymous Profile', 'More'][index],
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: textDark),
              ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatInboxScreen(isListener: false)),
                );
                _refreshNav();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(7.5),
                decoration: BoxDecoration(
                  color: softPeach,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCDFD5), width: 1.0),
                ),
                child: Badge(
                  isLabelVisible: chatUnreadCount > 0,
                  backgroundColor: const Color(0xFFEF4444),
                  textColor: Colors.white,
                  label: Text(
                    chatUnreadCount > 99 ? '99+' : '$chatUnreadCount',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 19, color: primaryOrange),
                ),
              ),
            ),
          ),
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
          height: 62,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
