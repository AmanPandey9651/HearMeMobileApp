import 'package:flutter/foundation.dart';
import '../models/app_models.dart';

class ActiveCallManager extends ChangeNotifier {
  static final ActiveCallManager instance = ActiveCallManager._();
  ActiveCallManager._();

  InstantSessionModel? activeSession;
  bool isCaller = false;
  bool isMinimized = false;
  int elapsedSeconds = 0;
  bool isMuted = false;
  bool isLive = false;

  VoidCallback? onToggleMute;
  VoidCallback? onEndCall;
  VoidCallback? onMaximizeCall;

  bool get hasActiveCall => activeSession != null && !activeSession!.ended;

  String get timeString {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void startCall(
    InstantSessionModel session, {
    required bool callerSide,
    VoidCallback? toggleMute,
    VoidCallback? endCall,
    VoidCallback? maximizeCall,
  }) {
    activeSession = session;
    isCaller = callerSide;
    isMinimized = false;
    elapsedSeconds = 0;
    isMuted = false;
    isLive = session.status == 'CONNECTED' || session.status == 'ACTIVE';
    onToggleMute = toggleMute;
    onEndCall = endCall;
    onMaximizeCall = maximizeCall;
    notifyListeners();
  }

  void bindCallControls({
    required VoidCallback toggleMute,
    required VoidCallback endCall,
    required VoidCallback maximizeCall,
  }) {
    onToggleMute = toggleMute;
    onEndCall = endCall;
    onMaximizeCall = maximizeCall;
  }

  void updateState({
    required int seconds,
    required bool muted,
    required bool live,
    InstantSessionModel? updatedSession,
  }) {
    var changed = false;
    if (elapsedSeconds != seconds) {
      elapsedSeconds = seconds;
      changed = true;
    }
    if (isMuted != muted) {
      isMuted = muted;
      changed = true;
    }
    if (isLive != live) {
      isLive = live;
      changed = true;
    }
    if (updatedSession != null && updatedSession.status != activeSession?.status) {
      activeSession = updatedSession;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void minimize() {
    if (!hasActiveCall) return;
    isMinimized = true;
    notifyListeners();
  }

  void maximize() {
    if (!hasActiveCall) return;
    isMinimized = false;
    notifyListeners();
    onMaximizeCall?.call();
  }

  void endCall() {
    onEndCall?.call();
  }

  void toggleMute() {
    onToggleMute?.call();
  }

  void clearCall() {
    activeSession = null;
    isMinimized = false;
    elapsedSeconds = 0;
    isMuted = false;
    isLive = false;
    onToggleMute = null;
    onEndCall = null;
    onMaximizeCall = null;
    notifyListeners();
  }
}
