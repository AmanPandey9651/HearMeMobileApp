import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:provider/provider.dart';
import '../core/app_controller.dart';
import '../models/app_models.dart';
import 'call_pulse_avatar.dart';
import 'common_widgets.dart';

class IncomingCallOverlay extends StatefulWidget {
  final InstantSessionModel session;
  final bool isCallback;

  const IncomingCallOverlay({
    super.key,
    required this.session,
    this.isCallback = false,
  });

  static Future<bool?> show(
    BuildContext context,
    InstantSessionModel session, {
    bool isCallback = false,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => IncomingCallOverlay(
        session: session,
        isCallback: isCallback,
      ),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
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

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  Timer? _countdownTimer;
  Timer? _vibrateTimer;
  Timer? _statusPollTimer;

  late int _secondsRemaining;
  int _elapsedRinging = 8;
  bool _actionTaken = false;

  String get peerName => widget.isCallback
      ? (widget.session.listenerName.isNotEmpty ? widget.session.listenerName : 'Listener')
      : (widget.session.callerNickname.isNotEmpty ? widget.session.callerNickname : 'Anonymous Caller');

  String? get peerAvatar => widget.isCallback
      ? widget.session.listenerAvatarUrl
      : widget.session.callerAvatarUrl;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = _calculateRemainingSeconds();
    _startRingtoneAndVibration();
    _startCountdown();
    _startStatusPolling();
  }

  int _calculateRemainingSeconds() {
    final expires = DateTime.tryParse(widget.session.expiresAt ?? '')?.toLocal();
    if (expires == null) return 45;
    final diff = expires.difference(DateTime.now()).inSeconds;
    if (diff <= 0 || diff > 45) return 45;
    return diff.toInt();
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
          _elapsedRinging++;
        });
      }
    });
  }

  void _startStatusPolling() {
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
                      ? 'Call request was cancelled'
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
    super.dispose();
  }

  String _formatTimer() {
    final m = (_elapsedRinging ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedRinging % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _handleDecline();
        });
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF5EE),
        body: SafeArea(
          child: Column(
            children: [
              // Top Navigation Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                      onPressed: () => _handleDecline(),
                    ),
                    const SizedBox(width: 4),
                    // Small circular avatar
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFECE5),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: peerAvatar != null && peerAvatar!.isNotEmpty
                            ? RemoteAvatar(
                                url: peerAvatar,
                                radius: 16,
                                fallback: peerName,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: Color(0xFFF95B3D),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF0F172A), size: 22),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Animated Pulsing Avatar Centerpiece
              Center(
                child: CallPulseAvatar(
                  name: peerName,
                  avatarUrl: peerAvatar,
                  size: 200,
                ),
              ),

              const SizedBox(height: 18),

              // Status Pill: ● INCOMING
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECE5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF95B3D),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'INCOMING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF95B3D),
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Peer Name Heading
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  peerName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Subtitle
              Text(
                widget.isCallback ? 'Incoming callback…' : 'Incoming call…',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 20),

              // Large Big Timer Display: 00:08 / tap to answer
              Text(
                _formatTimer(),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF95B3D),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'tap to answer',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 24),

              // Info Row: Phone icon + Someone is trying to reach you
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.phone_rounded,
                    size: 15,
                    color: Color(0xFFF95B3D),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isCallback
                        ? 'Listener is calling you back.'
                        : 'Someone is trying to reach you.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Two Action Buttons: Decline and Accept
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
                    // Decline Button
                    Expanded(
                      child: InkWell(
                        onTap: () => _handleDecline(),
                        borderRadius: BorderRadius.circular(26),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: const Color(0xFFF95B3D),
                              width: 1.2,
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cancel_outlined,
                                size: 18,
                                color: Color(0xFFF95B3D),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Decline',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF95B3D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Accept Button
                    Expanded(
                      child: InkWell(
                        onTap: () => _handleAccept(),
                        borderRadius: BorderRadius.circular(26),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF95B3D),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Accept',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // Bottom Privacy Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFECE5).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFD4C4).withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECE5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 16,
                          color: Color(0xFFF95B3D),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: const Color(0xFFFFC5B2),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      const Expanded(
                        child: Text(
                          'Your conversation remains private and secure.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
