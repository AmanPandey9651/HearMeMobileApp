import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/common/first_time_onboarding_screen.dart';
import 'services/app_lock_service.dart';
import 'services/call_push_service.dart';
import 'services/pip_service.dart';
import 'core/active_call_manager.dart';
import 'widgets/app_lock_screen.dart';
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

  // Platform-specific Firebase initialization
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: kAndroidFirebaseOptions);
      }
    } catch (e) {
      debugPrint('[Firebase] Android initialization warning: $e');
    }
  } else if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('[Firebase] iOS initialization warning (GoogleService-Info.plist): $e');
    }
  }

  await CallPushService.instance.initialize();

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
    PipService.instance.initialize();
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
        // Do not lock the app if Picture-in-Picture or an active call is running
        if (PipService.instance.isPipMode.value || ActiveCallManager.instance.hasActiveCall) {
          return;
        }
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

    // Listeners undergo professional verification and route directly to listener screens
    if (app.user!.isListener) {
      if (app.isListenerVerified) {
        return const ListenerShell();
      }
      return const ListenerVerificationPendingScreen();
    }

    // Only regular customer callers complete the first-time caller onboarding
    if (app.user!.role == 'CUSTOMER' && !app.user!.termsAccepted) {
      return const FirstTimeOnboardingScreen();
    }

    return const CallerShell();
  }
}
