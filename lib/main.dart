import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_config.dart';
import 'core/app_controller.dart';
import 'core/app_theme.dart';
import 'core/inactivity_guard.dart';
import 'screens/caller/caller_shell.dart';
import 'screens/caller/public_home_screen.dart';
import 'screens/listener/listener_shell.dart';
import 'screens/listener/listener_verification_pending_screen.dart';
import 'widgets/global_call_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  runApp(ChangeNotifierProvider(create: (_) => AppController()..bootstrap(), child: const TalkStrangersApp()));
}

class TalkStrangersApp extends StatelessWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const TalkStrangersApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'HearMe',
        theme: AppTheme.light,
        builder: (context, child) => GlobalCallHost(child: child ?? const SizedBox.shrink()),
        home: const InactivityGuard(child: RootGate()),
      );
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (app.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAF5EE),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFF95B3D)),
        ),
      );
    }
    if (app.user == null) return const PublicHomeScreen();
    if (app.user!.isListener) {
      if (app.isListenerVerified) {
        return const ListenerShell();
      }
      return const ListenerVerificationPendingScreen();
    }
    return const CallerShell();
  }
}
