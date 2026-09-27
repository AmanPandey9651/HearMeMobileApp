import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_controller.dart';

class InactivityGuard extends StatefulWidget {
  final Widget child;
  const InactivityGuard({super.key, required this.child});

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  void _reset() {
    timer?.cancel();
    if (!mounted) return;
    final app = context.read<AppController>();
    final days = app.mobileInactivityDays > 0 ? app.mobileInactivityDays : 30;
    timer = Timer(Duration(days: days), _expire);
  }

  Future<void> _expire() async {
    if (!mounted) return;
    final app = context.read<AppController>();
    if (app.user == null) {
      _reset();
      return;
    }
    if (app.activeSessionCount > 0) {
      _reset();
      return;
    }
    await app.logout();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _reset(),
        onPointerMove: (_) => _reset(),
        onPointerSignal: (_) => _reset(),
        child: widget.child,
      );
}
