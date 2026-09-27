import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/incoming_call_overlay.dart';
import 'listener_dashboard_screen.dart';
import 'listener_earnings_screen.dart';
import 'listener_history_screen.dart';
import 'listener_more_screen.dart';
import 'listener_profile_screen.dart';

class ListenerShell extends StatefulWidget {
  const ListenerShell({super.key});

  @override
  State<ListenerShell> createState() => _ListenerShellState();
}

class _ListenerShellState extends State<ListenerShell> {
  int index = 0;
  Timer? poll;
  Timer? nudgePoll;
  String? shownId;
  String? shownNudgeId;
  int unreadCount = 0;

  late final List<Widget> pages = [
    ListenerDashboardScreen(onNavigateTab: (tabIndex) => setState(() => index = tabIndex)),
    const ListenerHistoryScreen(),
    const ListenerEarningsScreen(),
    const ListenerProfileScreen(),
    ListenerMoreScreen(onNavigateTab: (tabIndex) => setState(() => index = tabIndex)),
  ];

  @override
  void initState() {
    super.initState();
    poll = Timer.periodic(const Duration(milliseconds: 1000), (_) => _incoming());
    nudgePoll = Timer.periodic(const Duration(seconds: 30), (_) => _nudges());
    Future<void>.delayed(const Duration(milliseconds: 900), _nudges);
  }

  @override
  void dispose() {
    poll?.cancel();
    nudgePoll?.cancel();
    super.dispose();
  }

  Future<void> _incoming() async {
    try {
      final s = await context.read<AppController>().api.pendingListenerSession();
      if (s == null) {
        shownId = null;
        return;
      }
      if (s.id == shownId || !mounted) return;
      shownId = s.id;
      await _showIncoming(s);
    } catch (_) {}
  }



  Future<void> _nudges() async {
    if (!mounted) return;
    try {
      final rows = await context.read<AppController>().api.notifications(page: 0, size: 50);
      Map<String, dynamic>? nudge;
      var unread = 0;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final isUnread = m['isRead'] != true && m['readAt'] == null;
        if (isUnread) unread++;
        if (nudge == null && isUnread && '${m['type'] ?? ''}'.toUpperCase() == 'CALLER_NUDGE') {
          nudge = m;
        }
      }
      if (mounted && unreadCount != unread) setState(() => unreadCount = unread);
      if (nudge == null || !mounted) return;
      final selectedNudge = nudge;
      final id = '${selectedNudge['id'] ?? ''}';
      if (id.isEmpty || id == shownNudgeId) return;
      shownNudgeId = id;
      final goOnline = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('A caller is waiting'),
          content: Text(
            '${selectedNudge['content'] ?? selectedNudge['title'] ?? 'A caller nudged you to come online.'}\n\nGo online now to receive session requests.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Dismiss')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Go online'),
            ),
          ],
        ),
      );
      try {
        await context.read<AppController>().api.readNotification(id);
        if (goOnline == true) {
          await context.read<AppController>().api.updatePresence('ONLINE');
          if (mounted) {
            setState(() => index = 0);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are online now.')));
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _showIncoming(InstantSessionModel s) async {
    final decision = await IncomingCallOverlay.show(context, s);

    try {
      if (decision == true) {
        final accepted = await context.read<AppController>().api.acceptSession(s.id);
        ActiveCallManager.instance.startCall(accepted, callerSide: false);
      } else if (decision == false) {
        await context.read<AppController>().api.rejectSession(s.id, 'Listener declined');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    shownId = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      appBar: null,
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1E6D8), width: 0.9)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFFFECE5),
          onDestinationSelected: (v) => setState(() => index = v),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFFF95B3D)),
              label: 'Dashboard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFFF95B3D)),
              label: 'Attendance',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded),
              selectedIcon: Icon(Icons.bar_chart_rounded, color: Color(0xFFF95B3D)),
              label: 'Earnings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: Color(0xFFF95B3D)),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.more_horiz_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
                child: const Icon(Icons.more_horiz_rounded, color: Color(0xFFF95B3D)),
              ),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
