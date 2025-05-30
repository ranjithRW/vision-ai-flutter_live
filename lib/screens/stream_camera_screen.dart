import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/stream_controller.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/main_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';

class StreamCameraScreen extends StatelessWidget {
  const StreamCameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final controller = Get.put(StreamCameraController(isLive: true));

    // Create a global key for the camera preview container
    final GlobalKey previewContainerKey = GlobalKey();

    // Set the key in controller
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.setWidgetKey(previewContainerKey);
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Get.offAll(const MainScreen());
        }
      },
      child: Scaffold(
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
              icon:
                  AppIcons.backIcon(themeController.currentTheme.primaryColor),
              onPressed: () {
                Get.offAll(const MainScreen());
              },
            );
          }),
          actions: [
            // Add streaming toggle button
            Obx(() {
              return IconButton(
                icon: Icon(
                  controller.isStreaming.value ? Icons.stop : Icons.play_arrow,
                  color: controller.isStreaming.value
                      ? Colors.red
                      : themeController.currentTheme.primaryColor,
                ),
                onPressed: () async {
                  await controller.toggleStreaming();
                },
              );
            }),
          ],
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

              // Camera preview + bounding boxes (This is what we'll stream)
              Padding(
                padding: AppPaddings.medium,
                child: Center(
                  child: controller.isCameraInitialized.value
                      ? RepaintBoundary(
                          key: previewContainerKey, // Key for capturing
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.center,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: controller.cameraController.value
                                      .previewSize!.height,
                                  height: controller.cameraController.value
                                      .previewSize!.width,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CameraPreview(
                                          controller.cameraController),
                                      // CustomPaint(
                                      //   painter: BoundingBoxPainter(
                                      //     boxes: controller.detectedObjects
                                      //         .toList(),
                                      //     imageSize: controller.cameraController
                                      //         .value.previewSize!,
                                      //     widgetSize:
                                      //         MediaQuery.of(context).size,
                                      //   ),
                                      // ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: themeController.currentTheme.primaryColor,
                          ),
                        ),
                ),
              ),

              // Streaming status indicator
              Positioned(
                top: 100,
                right: 20,
                child: Obx(() {
                  return controller.isStreaming.value
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink();
                }),
              ),
            ],
          );
        }),
      ),
    );
  }
}
