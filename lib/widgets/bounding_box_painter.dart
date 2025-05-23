import 'package:flutter/material.dart';
import 'package:vision_ai_app/model_classes/recognized_object.dart';

class BoundingBoxPainter extends CustomPainter {
  final List<RecognizedObject> boxes;
  final Size
      imageSize; // The actual camera image size, e.g. 640x480 (width, height)
  final Size widgetSize; // Size of the widget displaying the camera preview

  BoundingBoxPainter({
    required this.boxes,
    required this.imageSize,
    required this.widgetSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    for (var box in boxes) {
      // box.rect.left, top, width, height are in absolute pixels relative to imageSize

      final left = box.rect.left * scaleX;
      final top = box.rect.top * scaleY;
      final right = (box.rect.left + box.rect.width) * scaleX;
      final bottom = (box.rect.top + box.rect.height) * scaleY;

      final rect = Rect.fromLTRB(left, top, right, bottom);

      canvas.drawRect(rect, paint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '${box.label} ${(box.confidence * 100).toStringAsFixed(1)}%',
          style: const TextStyle(
            color: Colors.white,
            backgroundColor: Colors.red,
            fontSize: 14,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Draw label above the box (or inside with some padding)
      textPainter.paint(canvas, Offset(left, top - 20));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.boxes != boxes;
  }
}
