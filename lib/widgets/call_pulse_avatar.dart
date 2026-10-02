import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'common_widgets.dart';

class CallPulseAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final double size;
  final String? serviceType; // 'AUDIO_CALL', 'VIDEO_CALL', 'CHAT'

  const CallPulseAvatar({
    super.key,
    this.avatarUrl,
    required this.name,
    this.size = 200,
    this.serviceType,
  });

  @override
  State<CallPulseAvatar> createState() => _CallPulseAvatarState();
}

class _CallPulseAvatarState extends State<CallPulseAvatar> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _rotationController;

  bool get isVideo => widget.serviceType == 'VIDEO_CALL';
  bool get isChat => widget.serviceType == 'CHAT';

  Color get accentColor => isVideo
      ? const Color(0xFF7C3AED) // Royal Violet
      : (isChat ? const Color(0xFF059669) : const Color(0xFFF95B3D)); // Emerald / Coral

  Color get ringBgColor => isVideo
      ? const Color(0xFFF3E8FF)
      : (isChat ? const Color(0xFFECFDF5) : const Color(0xFFFFECE5));

  Color get ringBorderColor => isVideo
      ? const Color(0xFFDDD6FE)
      : (isChat ? const Color(0xFFA7F3D0) : const Color(0xFFFFD3C4));

  IconData get badgeIcon => isVideo
      ? Icons.videocam_rounded
      : (isChat ? Icons.chat_bubble_rounded : Icons.call_rounded);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _rotationController]),
      builder: (context, _) {
        final pulse = _pulseAnimation.value;
        final rotation = _rotationController.value * 2 * math.pi;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Left indicators: Soundwaves for Audio, Viewfinder for Video, Speech Bubbles for Chat
              Positioned(
                left: 10 - (pulse * 3),
                child: Opacity(
                  opacity: (0.45 + (pulse * 0.45)).clamp(0.0, 1.0),
                  child: isVideo
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ViewfinderBracket(isLeft: true, height: 42, strokeWidth: 2.2, opacity: 0.7 + (pulse * 0.3), color: accentColor),
                          ],
                        )
                      : isChat
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ChatFloatingBubble(isLeft: true, size: 26, opacity: 0.8 + (pulse * 0.2), color: accentColor),
                                const SizedBox(height: 6),
                                _ChatFloatingBubble(isLeft: true, size: 20, opacity: 0.5 + (pulse * 0.3), color: accentColor),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _WaveArc(isLeft: true, height: 38, strokeWidth: 2.2, opacity: 0.4 + (pulse * 0.4), color: accentColor),
                                const SizedBox(width: 4),
                                _WaveArc(isLeft: true, height: 50, strokeWidth: 2.6, opacity: 0.6 + (pulse * 0.4), color: accentColor),
                              ],
                            ),
                ),
              ),

              // Right indicators: Soundwaves for Audio, Viewfinder for Video, Speech Bubbles for Chat
              Positioned(
                right: 10 - (pulse * 3),
                child: Opacity(
                  opacity: (0.45 + (pulse * 0.45)).clamp(0.0, 1.0),
                  child: isVideo
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ViewfinderBracket(isLeft: false, height: 42, strokeWidth: 2.2, opacity: 0.7 + (pulse * 0.3), color: accentColor),
                          ],
                        )
                      : isChat
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _ChatFloatingBubble(isLeft: false, size: 20, opacity: 0.5 + (pulse * 0.3), color: accentColor),
                                const SizedBox(height: 6),
                                _ChatFloatingBubble(isLeft: false, size: 26, opacity: 0.8 + (pulse * 0.2), color: accentColor),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _WaveArc(isLeft: false, height: 50, strokeWidth: 2.6, opacity: 0.6 + (pulse * 0.4), color: accentColor),
                                const SizedBox(width: 4),
                                _WaveArc(isLeft: false, height: 38, strokeWidth: 2.2, opacity: 0.4 + (pulse * 0.4), color: accentColor),
                              ],
                            ),
                ),
              ),

              // Outer Ring 2
              Container(
                width: 152 + (pulse * 6),
                height: 152 + (pulse * 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringBgColor.withValues(alpha: 0.3),
                  border: Border.all(
                    color: ringBorderColor.withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
              ),

              // Outer Ring 1
              Container(
                width: 130 + (pulse * 4),
                height: 130 + (pulse * 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringBgColor.withValues(alpha: 0.5),
                  border: Border.all(
                    color: ringBorderColor.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
              ),

              // Rotating Progress Arc with service accent
              Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  size: const Size(130, 130),
                  painter: _ArcPainter(
                    color: accentColor,
                    strokeWidth: 3.2,
                    sweepAngle: 1.25,
                  ),
                ),
              ),

              // Center Avatar Circle with Service Badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ringBgColor,
                      border: Border.all(
                        color: ringBorderColor,
                        width: 1.6,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                          ? RemoteAvatar(
                              url: widget.avatarUrl,
                              radius: 48,
                              fallback: widget.name,
                            )
                          : Center(
                              child: Icon(
                                Icons.person_rounded,
                                size: 52,
                                color: accentColor.withValues(alpha: 0.85),
                              ),
                            ),
                    ),
                  ),

                  // Service Badge Pill at bottom right of avatar
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          badgeIcon,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WaveArc extends StatelessWidget {
  final bool isLeft;
  final double height;
  final double strokeWidth;
  final double opacity;
  final Color color;

  const _WaveArc({
    required this.isLeft,
    required this.height,
    required this.strokeWidth,
    required this.opacity,
    this.color = const Color(0xFFF95B3D),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(strokeWidth * 3, height),
      painter: _SoundWavePainter(
        isLeft: isLeft,
        strokeWidth: strokeWidth,
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _ViewfinderBracket extends StatelessWidget {
  final bool isLeft;
  final double height;
  final double strokeWidth;
  final double opacity;
  final Color color;

  const _ViewfinderBracket({
    required this.isLeft,
    required this.height,
    required this.strokeWidth,
    required this.opacity,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(strokeWidth * 4.5, height),
      painter: _ViewfinderPainter(
        isLeft: isLeft,
        strokeWidth: strokeWidth,
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  final bool isLeft;
  final double strokeWidth;
  final Color color;

  _ViewfinderPainter({
    required this.isLeft,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final corner = size.width * 0.75;
    if (isLeft) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width - corner, 0);
      path.lineTo(size.width - corner, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(corner, 0);
      path.lineTo(corner, size.height);
      path.lineTo(0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class _ChatFloatingBubble extends StatelessWidget {
  final bool isLeft;
  final double size;
  final double opacity;
  final Color color;

  const _ChatFloatingBubble({
    required this.isLeft,
    required this.size,
    required this.opacity,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 0.82,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
          bottomLeft: Radius.circular(isLeft ? 2 : 8),
          bottomRight: Radius.circular(isLeft ? 8 : 2),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: (opacity * 0.3).clamp(0.0, 1.0)),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 1.8),
            Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
            const SizedBox(width: 1.8),
            Container(width: 2.2, height: 2.2, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}

class _SoundWavePainter extends CustomPainter {
  final bool isLeft;
  final double strokeWidth;
  final Color color;

  _SoundWavePainter({
    required this.isLeft,
    required this.strokeWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (isLeft) {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(0, size.height / 2, size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.quadraticBezierTo(size.width, size.height / 2, 0, size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SoundWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

class _ArcPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double sweepAngle;

  _ArcPainter({
    required this.color,
    required this.strokeWidth,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.sweepAngle != sweepAngle;
}
