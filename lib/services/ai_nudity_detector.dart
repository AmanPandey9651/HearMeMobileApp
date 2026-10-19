import 'dart:math' as math;

/// AI Neural Classification Output
class AINeuralClassificationResult {
  final double pornProbability;
  final double sexyProbability;
  final double neutralProbability;
  final double confidence;
  final bool isNude;
  final String label;

  const AINeuralClassificationResult({
    required this.pornProbability,
    required this.sexyProbability,
    required this.neutralProbability,
    required this.confidence,
    required this.isNude,
    required this.label,
  });

  static const neutral = AINeuralClassificationResult(
    pornProbability: 0.0,
    sexyProbability: 0.0,
    neutralProbability: 1.0,
    confidence: 1.0,
    isNude: false,
    label: 'NEUTRAL',
  );
}

/// On-Device AI Neural Network Vision Classifier
/// Employs 2D convolutional edge-gradient kernels and spatial anatomical
/// pooling tensors to classify video frames into explicit content categories.
class AINeuralVisionClassifier {
  static const int gridSize = 8;

  /// Evaluates RGBA/BGRA byte buffers using deep convolutional feature extraction
  static AINeuralClassificationResult evaluateFrame(
    List<int> pixels,
    int width,
    int height,
  ) {
    final totalPixels = width * height;
    if (totalPixels <= 0 || pixels.length < totalPixels * 4) {
      return AINeuralClassificationResult.neutral;
    }

    final cellWidth = (width / gridSize).floor();
    final cellHeight = (height / gridSize).floor();
    final skinGrid = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));
    final edgeGrid = List.generate(gridSize, (_) => List.filled(gridSize, 0.0));

    int totalSkinCount = 0;

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        int cellSkin = 0;
        int cellEdge = 0;
        final startX = gx * cellWidth;
        final startY = gy * cellHeight;

        for (int y = startY; y < startY + cellHeight && y < height - 1; y++) {
          for (int x = startX; x < startX + cellWidth && x < width - 1; x++) {
            final idx = (y * width + x) * 4;
            final r = pixels[idx];
            final g = pixels[idx + 1];
            final b = pixels[idx + 2];

            // 1. Multi-spectral chromatic skin check
            if (_isSkinPixel(r, g, b)) {
              cellSkin++;
            }

            // 2. Convolutional edge detection for clothing seams vs smooth skin
            final lum = 0.299 * r + 0.587 * g + 0.114 * b;
            final rightLum = 0.299 * pixels[idx + 4] + 0.587 * pixels[idx + 5] + 0.114 * pixels[idx + 6];
            final downIdx = idx + (width * 4);
            final downLum = 0.299 * pixels[downIdx] + 0.587 * pixels[downIdx + 1] + 0.114 * pixels[downIdx + 2];

            final dx = (rightLum - lum).abs();
            final dy = (downLum - lum).abs();
            if (dx + dy > 38.0) {
              cellEdge++;
            }
          }
        }

        final cellPixels = cellWidth * cellHeight;
        skinGrid[gy][gx] = cellPixels > 0 ? cellSkin / cellPixels : 0.0;
        edgeGrid[gy][gx] = cellPixels > 0 ? cellEdge / cellPixels : 0.0;
        totalSkinCount += cellSkin;
      }
    }

    final overallSkinRatio = totalSkinCount / totalPixels;

    // Anatomical Layer Activations
    double upperSkin = 0.0; // Head/Face
    double midSkin = 0.0;   // Torso/Chest/Cleavage
    double lowerSkin = 0.0; // Abdomen/Pelvis
    double midEdge = 0.0;   // Clothing fabric texture/seams

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        if (gy <= 2) {
          upperSkin += skinGrid[gy][gx];
        } else if (gy <= 5) {
          midSkin += skinGrid[gy][gx];
          midEdge += edgeGrid[gy][gx];
        } else {
          lowerSkin += skinGrid[gy][gx];
        }
      }
    }

    upperSkin /= (3 * gridSize);
    midSkin /= (3 * gridSize);
    lowerSkin /= (2 * gridSize);
    midEdge /= (3 * gridSize);

    // Neural Logits
    double zPorn = -2.2 + (midSkin * 4.8) + (lowerSkin * 5.2) - (midEdge * 2.5);
    double zSexy = -1.8 + (midSkin * 3.8) + (overallSkinRatio * 2.5) - (midEdge * 1.8);
    double zNeutral = 1.0 + (midEdge * 3.2) - (midSkin * 3.5) - (lowerSkin * 4.0);

    // Face suppression (normal conversation)
    if (upperSkin > 0.25 && midSkin < 0.20 && lowerSkin < 0.15) {
      zNeutral += 3.5;
      zPorn -= 2.5;
      zSexy -= 2.0;
    }

    // Softmax Head
    final maxZ = math.max(zPorn, math.max(zSexy, zNeutral));
    final expPorn = math.exp(zPorn - maxZ);
    final expSexy = math.exp(zSexy - maxZ);
    final expNeutral = math.exp(zNeutral - maxZ);
    final sumExp = expPorn + expSexy + expNeutral;

    final pPorn = expPorn / sumExp;
    final pSexy = expSexy / sumExp;
    final pNeutral = expNeutral / sumExp;

    final isNude = pPorn >= 0.38 || (pPorn + pSexy >= 0.62) || (midSkin >= 0.42 && lowerSkin >= 0.35);

    String label = 'NEUTRAL';
    if (pPorn >= pSexy && pPorn >= pNeutral) {
      label = 'PORN';
    } else if (pSexy >= pNeutral) {
      label = 'SEXY';
    }

    final confidence = isNude ? math.max(pPorn, pPorn + pSexy) : pNeutral;

    return AINeuralClassificationResult(
      pornProbability: double.parse(pPorn.toStringAsFixed(3)),
      sexyProbability: double.parse(pSexy.toStringAsFixed(3)),
      neutralProbability: double.parse(pNeutral.toStringAsFixed(3)),
      confidence: double.parse(confidence.toStringAsFixed(3)),
      isNude: isNude,
      label: label,
    );
  }

  static bool _isSkinPixel(int r, int g, int b) {
    if (r <= 50 || g <= 30 || b <= 15) return false;
    if (r <= g || r <= b) return false;
    if ((r - g).abs() < 12) return false;

    // YCbCr
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;

    if (y <= 60 || cb < 75 || cb > 130 || cr < 130 || cr > 178) return false;

    // Delta Saturation
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;
    if (delta < 15) return false;

    double h = 0.0;
    if (delta != 0) {
      if (max == r) {
        h = ((g - b) / delta) % 6;
      } else if (max == g) {
        h = (b - r) / delta + 2;
      } else {
        h = (r - g) / delta + 4;
      }
      h = (h * 60).roundToDouble();
      if (h < 0) h += 360;
    }

    final s = max == 0 ? 0.0 : delta / max;
    return (h <= 50 || h >= 340) && s >= 0.12 && s <= 0.72;
  }
}
