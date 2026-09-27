import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';
import '../core/app_controller.dart';
import '../models/app_models.dart';
import 'common_widgets.dart';

class IncomingCallOverlay extends StatefulWidget {
  final InstantSessionModel session;

  const IncomingCallOverlay({super.key, required this.session});

  static Future<bool?> show(BuildContext context, InstantSessionModel session) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) => IncomingCallOverlay(session: session),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _buttonGlowController;
  late final Animation<double> _buttonGlowAnimation;

  Timer? _countdownTimer;
  Timer? _vibrateTimer;
  Timer? _statusPollTimer;

  late int _secondsRemaining;
  bool _actionTaken = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _calculateRemainingSeconds();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutQuad,
    );

    _buttonGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _buttonGlowAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _buttonGlowController, curve: Curves.easeInOut),
    );

    _startRingtoneAndVibration();
    _startCountdown();
    _startStatusPolling();
  }

  int _calculateRemainingSeconds() {
    final expires = DateTime.tryParse(widget.session.expiresAt ?? '')?.toLocal();
    if (expires == null) return 45;
    final diff = expires.difference(DateTime.now()).inSeconds;
    return diff.clamp(0, 45).toInt();
  }

  void _startRingtoneAndVibration() {
    try {
      FlutterRingtonePlayer().playRingtone(
        volume: 1.0,
        looping: true,
        asAlarm: false,
      );
    } catch (_) {}

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      try {
        HapticFeedback.vibrate();
      } catch (_) {}
    });
  }

  void _stopRingtoneAndVibration() {
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _handleDecline(timeout: true);
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _startStatusPolling() {
    // Check if the caller hung up or session was cancelled
    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (_actionTaken || !mounted) return;
      try {
        final current = await context.read<AppController>().api.session(widget.session.id);
        if (_actionTaken || !mounted) return;
        if (current.ended || current.status != 'REQUESTED') {
          _stopRingtoneAndVibration();
          _actionTaken = true;
          if (mounted) {
            Navigator.of(context).pop(null);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  current.status == 'CANCELLED'
                      ? 'Caller cancelled the request'
                      : 'Call request expired',
                ),
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (_) {}
    });
  }

  void _handleAccept() {
    if (_actionTaken) return;
    _actionTaken = true;
    _stopRingtoneAndVibration();
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop(true);
  }

  void _handleDecline({bool timeout = false}) {
    if (_actionTaken) return;
    _actionTaken = true;
    _stopRingtoneAndVibration();
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _stopRingtoneAndVibration();
    _countdownTimer?.cancel();
    _statusPollTimer?.cancel();
    _pulseController.dispose();
    _buttonGlowController.dispose();
    super.dispose();
  }

  Color get _sessionColor {
    switch (widget.session.type) {
      case 'VIDEO_CALL':
        return const Color(0xFF8B5CF6);
      case 'CHAT':
        return const Color(0xFF0EA5E9);
      default:
        return const Color(0xFFF95B3D);
    }
  }

  IconData get _sessionIcon {
    switch (widget.session.type) {
      case 'VIDEO_CALL':
        return Icons.videocam_rounded;
      case 'CHAT':
        return Icons.chat_bubble_rounded;
      default:
        return Icons.phone_in_talk_rounded;
    }
  }

  String get _sessionTypeLabel {
    switch (widget.session.type) {
      case 'VIDEO_CALL':
        return 'Incoming Video Call';
      case 'CHAT':
        return 'Incoming Chat Request';
      default:
        return 'Incoming Voice Call';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleDecline();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0B1120),
                Color(0xFF0F172A),
                Color(0xFF1E1B4B),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                children: [
                  // Top Security & Privacy Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'PRIVATE & ANONYMOUS CALL',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Animated Ripple Avatar Centerpiece
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Wave 3
                            Container(
                              width: 140 + (_pulseAnimation.value * 70),
                              height: 140 + (_pulseAnimation.value * 70),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _sessionColor.withValues(
                                  alpha: ((1 - _pulseAnimation.value) * 0.18).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                            // Wave 2
                            Container(
                              width: 120 + (_pulseAnimation.value * 45),
                              height: 120 + (_pulseAnimation.value * 45),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _sessionColor.withValues(
                                  alpha: ((1 - _pulseAnimation.value) * 0.32).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                            // Wave 1
                            Container(
                              width: 105 + (_pulseAnimation.value * 25),
                              height: 105 + (_pulseAnimation.value * 25),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _sessionColor.withValues(
                                  alpha: ((1 - _pulseAnimation.value) * 0.45).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                            // Avatar border glow
                            Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    _sessionColor,
                                    Colors.white.withValues(alpha: 0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _sessionColor.withValues(alpha: 0.4),
                                    blurRadius: 28,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(4),
                              child: ClipOval(
                                child: RemoteAvatar(
                                  url: widget.session.callerAvatarUrl,
                                  radius: 52,
                                  fallback: widget.session.callerNickname,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // Caller Anonymous Nickname
                  Text(
                    widget.session.callerNickname,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Session Type Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _sessionColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _sessionColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_sessionIcon, size: 16, color: _sessionColor),
                        const SizedBox(width: 8),
                        Text(
                          _sessionTypeLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Rate / Earnings Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.monetization_on_outlined,
                          size: 15,
                          color: Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Earning: ₹${widget.session.ratePerMinute.toStringAsFixed(0)} / min',
                          style: const TextStyle(
                            color: Color(0xFFFBBF24),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 3),

                  // Countdown Timer Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _secondsRemaining <= 10
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _secondsRemaining <= 10
                            ? Colors.redAccent.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: _secondsRemaining <= 10
                              ? Colors.redAccent
                              : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Window closes in ${_secondsRemaining}s',
                          style: TextStyle(
                            color: _secondsRemaining <= 10
                                ? Colors.redAccent
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Action Buttons Row (Decline vs Accept)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // DECLINE BUTTON
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => _handleDecline(),
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFEF4444),
                                      Color(0xFFDC2626),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                      blurRadius: 18,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.call_end_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Decline',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),

                        // ACCEPT BUTTON
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _buttonGlowAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _buttonGlowAnimation.value,
                                  child: child,
                                );
                              },
                              child: GestureDetector(
                                onTap: _handleAccept,
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF10B981),
                                        Color(0xFF059669),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.55),
                                        blurRadius: 22,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.call_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Accept',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
