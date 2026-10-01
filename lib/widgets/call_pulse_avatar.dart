import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'common_widgets.dart';

class CallPulseAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final double size;

  const CallPulseAvatar({
    super.key,
    this.avatarUrl,
    required this.name,
    this.size = 200,
  });

  @override
  State<CallPulseAvatar> createState() => _CallPulseAvatarState();
}

class _CallPulseAvatarState extends State<CallPulseAvatar> with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final AnimationController _rotationController;

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
              // Left soundwaves ((
              Positioned(
                left: 10 - (pulse * 3),
                child: Opacity(
                  opacity: (0.45 + (pulse * 0.45)).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WaveArc(isLeft: true, height: 38, strokeWidth: 2.2, opacity: 0.4 + (pulse * 0.4)),
                      const SizedBox(width: 4),
                      _WaveArc(isLeft: true, height: 50, strokeWidth: 2.6, opacity: 0.6 + (pulse * 0.4)),
                    ],
                  ),
                ),
              ),

              // Right soundwaves ))
              Positioned(
                right: 10 - (pulse * 3),
                child: Opacity(
                  opacity: (0.45 + (pulse * 0.45)).clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WaveArc(isLeft: false, height: 50, strokeWidth: 2.6, opacity: 0.6 + (pulse * 0.4)),
                      const SizedBox(width: 4),
                      _WaveArc(isLeft: false, height: 38, strokeWidth: 2.2, opacity: 0.4 + (pulse * 0.4)),
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
                  color: const Color(0xFFFFECE5).withValues(alpha: 0.25),
                  border: Border.all(
                    color: const Color(0xFFFFE0D4).withValues(alpha: 0.55),
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
                  color: const Color(0xFFFFECE5).withValues(alpha: 0.45),
                  border: Border.all(
                    color: const Color(0xFFFFD3C4).withValues(alpha: 0.75),
                    width: 1.5,
                  ),
                ),
              ),

              // Rotating Progress Arc
              Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  size: const Size(130, 130),
                  painter: _ArcPainter(
                    color: const Color(0xFFF95B3D),
                    strokeWidth: 3.2,
                    sweepAngle: 1.25,
                  ),
                ),
              ),

              // Center Avatar Circle
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFECE5),
                  border: Border.all(
                    color: const Color(0xFFFFD2C2),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF95B3D).withValues(alpha: 0.12),
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
                            color: const Color(0xFFF95B3D).withValues(alpha: 0.85),
                          ),
                        ),
                ),
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

  const _WaveArc({
    required this.isLeft,
    required this.height,
    required this.strokeWidth,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(strokeWidth * 3, height),
      painter: _SoundWavePainter(
        isLeft: isLeft,
        strokeWidth: strokeWidth,
        color: const Color(0xFFF95B3D).withValues(alpha: opacity.clamp(0.0, 1.0)),
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
