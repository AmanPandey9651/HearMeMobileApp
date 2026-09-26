import 'package:flutter/material.dart';

class VideoPrivacyFilter {
  static const none = 'NONE';
  static const studioBlur = 'STUDIO_BLUR';
  static const cyberMask = 'CYBER_MASK';
  static const foxMask = 'CAT_FOX_MASK';
  static const comic = 'COMIC_ANONYMOUS';

  static const options = <Map<String, String>>[
    {'id': none, 'label': 'Original Camera', 'emoji': '📷', 'description': 'Clean unaltered video'},
    {'id': studioBlur, 'label': 'Soft Studio', 'emoji': '✨', 'description': 'Contrast, soft vignette and privacy styling'},
    {'id': cyberMask, 'label': 'Cyber Visor Mask', 'emoji': '🥽', 'description': 'Futuristic privacy visor'},
    {'id': foxMask, 'label': 'Fox Disguise', 'emoji': '🦊', 'description': 'Playful animal privacy mask'},
    {'id': comic, 'label': 'Comic Noir', 'emoji': '🎨', 'description': 'High-contrast monochrome identity styling'},
  ];
}

class FilteredVideoView extends StatelessWidget {
  final String filter;
  final Widget child;
  final bool showBadge;

  const FilteredVideoView({super.key, required this.filter, required this.child, this.showBadge = true});

  @override
  Widget build(BuildContext context) {
    Widget base = child;
    if (filter == VideoPrivacyFilter.comic) {
      base = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          .42, .42, .42, 0, -35,
          .42, .42, .42, 0, -35,
          .42, .42, .42, 0, -35,
          0, 0, 0, 1, 0,
        ]),
        child: base,
      );
    } else if (filter == VideoPrivacyFilter.studioBlur) {
      base = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          1.08, 0, 0, 0, 4,
          0, 1.08, 0, 0, 4,
          0, 0, 1.08, 0, 4,
          0, 0, 0, 1, 0,
        ]),
        child: base,
      );
    }

    return LayoutBuilder(
      builder: (context, c) => Stack(
        fit: StackFit.expand,
        children: [
          base,
          if (filter == VideoPrivacyFilter.studioBlur)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(.42)],
                    stops: const [.45, 1],
                  ),
                ),
              ),
            ),
          if (filter == VideoPrivacyFilter.cyberMask) _cyber(c),
          if (filter == VideoPrivacyFilter.foxMask) _fox(c),
          if (filter == VideoPrivacyFilter.comic && showBadge)
            const Positioned(left: 10, top: 10, child: _FilterBadge(text: '🛡 IDENTITY MASKED')),
        ],
      ),
    );
  }

  Widget _cyber(BoxConstraints c) {
    final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
    final h = c.maxHeight.isFinite ? c.maxHeight : 400.0;
    final visorW = w * .67;
    final visorH = (h * .16).clamp(38.0, 100.0);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            left: (w - visorW) / 2,
            top: h * .29,
            width: visorW,
            height: visorH,
            child: CustomPaint(painter: _CyberPainter()),
          ),
          if (showBadge) const Positioned(left: 10, top: 10, child: _FilterBadge(text: '🥽 ANON//ACTIVE')),
        ],
      ),
    );
  }

  Widget _fox(BoxConstraints c) {
    final w = c.maxWidth.isFinite ? c.maxWidth : 300.0;
    final h = c.maxHeight.isFinite ? c.maxHeight : 400.0;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(left: w * .21, top: h * .08, child: Transform.rotate(angle: -.22, child: const Icon(Icons.change_history, size: 78, color: Colors.deepOrange))),
          Positioned(right: w * .21, top: h * .08, child: Transform.rotate(angle: .22, child: const Icon(Icons.change_history, size: 78, color: Colors.deepOrange))),
          Positioned(left: (w / 2) - 11, top: h * .47, child: Container(width: 22, height: 15, decoration: BoxDecoration(color: const Color(0xff172033), borderRadius: BorderRadius.circular(20)))),
          if (showBadge) const Positioned(left: 10, top: 10, child: _FilterBadge(text: '🦊 FOX DISGUISE')),
        ],
      ),
    );
  }
}

class _FilterBadge extends StatelessWidget {
  final String text;
  const _FilterBadge({required this.text});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
      );
}

class _CyberPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - 18, size.height)
      ..lineTo(18, size.height)
      ..close();
    final fill = Paint()..color = const Color(0x8806b6d4);
    final stroke = Paint()
      ..color = const Color(0xff22d3ee)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
    final tp = TextPainter(
      text: const TextSpan(text: 'ANON//ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
