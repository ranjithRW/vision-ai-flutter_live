import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/object_detection_controller.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/main_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';

class RealTimeCameraScreen extends StatelessWidget {
  const RealTimeCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final controller = Get.put(ObjectDetectionController());
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
              // Use Get.offAll instead of Navigator
              Get.offAll(() => const MainScreen());
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

            // Camera Preview with bounding boxes
            if (controller.isCameraInitialized.value)
              Center(
                child: Padding(
                  padding: AppPaddings.paddingAll12,
                  child: Positioned.fill(
                    child: Stack(
                      children: [
                        CameraPreview(controller.cameraController),
                        // CustomPaint(
                        //   painter: BoundingBoxPainter(controller.results),
                        //   child: Container(),
                        // ),
                      ],
                    ),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        );
      }),
    );
  }
}
