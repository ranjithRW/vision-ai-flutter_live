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
    // Clip to ensure nothing is drawn outside the canvas
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Use the size parameter (actual canvas size) instead of widgetSize for scaling
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (var box in boxes) {
      // Convert normalized coordinates (0-1) to actual pixel coordinates
      final actualLeft = box.rect.left * imageSize.width;
      final actualTop = box.rect.top * imageSize.height;
      final actualWidth = box.rect.width * imageSize.width;
      final actualHeight = box.rect.height * imageSize.height;

      // Scale to canvas size
      final left = (actualLeft * scaleX).clamp(0.0, size.width);
      final top = (actualTop * scaleY).clamp(0.0, size.height);
      final right = ((actualLeft + actualWidth) * scaleX).clamp(0.0, size.width);
      final bottom = ((actualTop + actualHeight) * scaleY).clamp(0.0, size.height);

      // Only draw if the box has valid dimensions
      if (right > left && bottom > top) {
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
        // Make sure the label doesn't go outside bounds
        final labelX = left.clamp(0.0, size.width - textPainter.width);
        final labelY = top > 20 ? top - 20 : top + 5;
        final clampedLabelY = labelY.clamp(0.0, size.height - textPainter.height);
        
        textPainter.paint(canvas, Offset(labelX, clampedLabelY));
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.boxes != boxes;
  }
}