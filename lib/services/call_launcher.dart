import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/active_call_manager.dart';
import '../core/app_controller.dart';
import '../models/app_models.dart';
import '../screens/auth/login_screen.dart';
import '../widgets/common_widgets.dart';

class CallLauncher {
  static bool _inProgress = false;

  /// Starts an instant call/video/chat directly in sub-second time without
  /// navigating through extra profile screens or blocking metadata calls.
  static Future<void> startDirectCall(
    BuildContext context,
    ListenerCardModel listener,
    String type, {
    String? categorySlug,
  }) async {
    if (_inProgress) return;

    final app = context.read<AppController>();
    if (app.user == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in to connect'),
          content: Text('Please log in or create an anonymous account to connect with ${listener.displayName}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Log In / Sign Up'),
            ),
          ],
        ),
      );
      return;
    }

    if (listener.presence != 'ONLINE') {
      if (listener.presence == 'BUSY_IN_CALL' || listener.presence == 'BUSY') {
        showError(context, '${listener.displayName} is currently in a call. Please choose another listener.');
      } else {
        showError(context, '${listener.displayName} is currently offline.');
      }
      return;
    }

    if (type == 'AUDIO_CALL' && !listener.audioAvailable) {
      showError(context, '${listener.displayName} is currently not accepting audio calls.');
      return;
    }
    if (type == 'VIDEO_CALL' && !listener.videoAvailable) {
      showError(context, '${listener.displayName} is currently not accepting video calls.');
      return;
    }
    if (type == 'CHAT' && !listener.chatAvailable) {
      showError(context, '${listener.displayName} is currently not accepting chat sessions.');
      return;
    }

    _inProgress = true;
    try {
      HapticFeedback.lightImpact();
      // Fast single-POST call initiation (< 300ms)
      final session = await app.api.requestSession(listener.id, type, categorySlug: categorySlug);
      ActiveCallManager.instance.startCall(session, callerSide: true);
    } catch (e) {
      showError(context, e);
    } finally {
      _inProgress = false;
    }
  }
}
