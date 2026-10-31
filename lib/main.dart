import 'services/app_lock_service.dart';
import 'widgets/app_lock_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
import 'widgets/feel_again_splash.dart';
import 'widgets/global_call_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyDpiYOYzu7NGZKQHP1qLlRkkM9CcXvZ-eE',
          appId: '1:972145849986:android:7e74ce33b40b3e98aea69b',
          messagingSenderId: '972145849986',
          projectId: 'feelback-536d4',
          storageBucket: 'feelback-536d4.firebasestorage.app',
        ),
      );
    } catch (e) {
      debugPrint('Firebase init warning: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()..bootstrap()),
        ChangeNotifierProvider(create: (_) => AppLockService()..init()),
      ],
      child: const FeelAgainApp(),
    ),
  );
}
typedef TalkStrangersApp = FeelAgainApp;
typedef FeelBackApp = FeelAgainApp;

class FeelAgainApp extends StatefulWidget {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const FeelAgainApp({super.key});

  @override
  State<FeelAgainApp> createState() => _FeelAgainAppState();
}

class _FeelAgainAppState extends State<FeelAgainApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted) {
        context.read<AppLockService>().lockApp();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final lockService = context.watch<AppLockService>();

    return MaterialApp(
      navigatorKey: FeelAgainApp.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: app.activeBrandName,
      theme: AppTheme.light,
      builder: (ctx, child) {
        final content = GlobalCallHost(child: child ?? const SizedBox.shrink());
        if (lockService.isLockEnabled && !lockService.isUnlocked) {
          return Stack(
            children: [
              content,
              Positioned.fill(
                child: AppLockScreen(
                  onUnlocked: () => lockService.unlock(),
                ),
              ),
            ],
          );
        }
        return content;
      },
      home: const InactivityGuard(child: RootGate()),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _splashFinished = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    // Show FeelAgain splash screen on startup, reload, and during logging in / logging out
    if (!_splashFinished || app.loading || app.showAuthSplash || app.isResolvingListenerStatus) {
      return FeelAgainSplashScreen(
        onComplete: () {
          if (mounted) {
            setState(() {
              _splashFinished = true;
            });
            if (app.showAuthSplash) {
              app.finishAuthSplash();
            }
          }
        },
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
