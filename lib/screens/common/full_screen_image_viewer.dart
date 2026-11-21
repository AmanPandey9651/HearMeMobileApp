import 'package:flutter/material.dart';
import '../../widgets/common_widgets.dart';

class FullScreenImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String displayName;
  final String? heroTag;

  const FullScreenImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.displayName,
    this.heroTag,
  });

  @override
  State<FullScreenImageViewerScreen> createState() => _FullScreenImageViewerScreenState();
}

class _FullScreenImageViewerScreenState extends State<FullScreenImageViewerScreen>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  TapDownDetails? _doubleTapDetails;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_animation != null) {
          _transformationController.value = _animation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final Matrix4 endMatrix;
    if (currentScale > 1.2) {
      // Zoom out to normal 1.0
      endMatrix = Matrix4.identity();
    } else {
      // Zoom in to 2.5x around tap position
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      final x = -position.dx * (2.5 - 1.0);
      final y = -position.dy * (2.5 - 1.0);
      endMatrix = Matrix4.identity()
        ..translate(x, y)
        ..scale(2.5);
    }

    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget = buildAvatarImage(
      widget.imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
            const SizedBox(height: 12),
            Text(
              'Could not load photo for ${widget.displayName}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );

    if (widget.heroTag != null) {
      imageWidget = Hero(
        tag: widget.heroTag!,
        child: imageWidget,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Zoomable & pannable full-screen interactive image
          GestureDetector(
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: 4.5,
              panEnabled: true,
              scaleEnabled: true,
              child: SizedBox.expand(
                child: Center(
                  child: imageWidget,
                ),
              ),
            ),
          ),

          // 2. Top App Bar with back/close and listener display name
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Close full view',
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 3. Subtle bottom helper overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Pinch or double-tap to zoom • Drag to explore',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
