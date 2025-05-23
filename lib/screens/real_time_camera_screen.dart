import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// import 'package:vision_ai_app/controllers/object_detection_controller_tflite.dart';
import 'package:vision_ai_app/controllers/object_detection_controller_tflite_v2.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/main_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';
import 'package:vision_ai_app/widgets/bounding_box_painter.dart';

class RealTimeCameraScreen extends StatelessWidget {
  const RealTimeCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final controller = Get.put(ObjectDetectionControllerTFLiteV2());
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Obx(() {
          return Text(
            "Live Detect",
            style: AppTextStyles.primaryTextStyle70020().copyWith(
              color: themeController.currentTheme.primaryColor,
            ),
          );
        }),
        leading: Obx(() {
          return IconButton(
            icon: AppIcons.backIcon(themeController.currentTheme.primaryColor),
            onPressed: () {
              Get.offAll(const MainScreen());
            },
          );
        }),
      ),
      body: Obx(() {
        return Stack(
          children: [
            // Gradient background
            Container(
              decoration: BoxDecoration(
                gradient: themeController.currentGradient,
              ),
            ),

            // Camera preview + bounding boxes
            Padding(
              padding: AppPaddings.medium,
              child: Center(
                child: controller.isCameraInitialized.value
                    ? ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: controller
                                  .cameraController.value.previewSize!.height,
                              height: controller
                                  .cameraController.value.previewSize!.width,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CameraPreview(controller.cameraController),
                                  CustomPaint(
                                    painter: BoundingBoxPainter(
                                      boxes:
                                          controller.detectedObjects.toList(),
                                      imageSize: controller
                                          .cameraController
                                          .value
                                          .previewSize!, // your model input size
                                      widgetSize: MediaQuery.of(context).size,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            )
          ],
        );
      }),
    );
  }
}
