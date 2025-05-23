import 'dart:ui';

class RecognizedObject {
  final Rect rect;
  final String label;
  final double confidence;

  RecognizedObject({
    required this.rect,
    required this.label,
    required this.confidence,
  });
}
