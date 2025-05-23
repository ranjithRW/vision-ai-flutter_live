import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/object_detection_controller_tflite.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/main_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/styles/button_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';
import 'package:vision_ai_app/widgets/custom_widgets.dart';

class ResultImageScreen extends StatelessWidget {
  const ResultImageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    final controller = Get.find<ObjectDetectionControllerTFLite>();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Obx(() {
          return Text(
            "Results",
            style: AppTextStyles.primaryTextStyle70020().copyWith(
              color: themeController.currentTheme.primaryColor,
            ),
          );
        }),
        leading: Obx(() {
          return IconButton(
            icon: AppIcons.backIcon(themeController.currentTheme.primaryColor),
            onPressed: () {
              Get.back();
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
            SafeArea(
              child: Padding(
                padding: AppPaddings.medium,
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: controller.imageAspectRatio.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: themeController.currentTheme.primaryColor
                                as Color,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            "Detected Image Preview",
                            style:
                                AppTextStyles.primaryTextStyle60016().copyWith(
                              color: themeController.currentTheme.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Gap(16.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          style: AppButtonStyles.mainMenuButtonStyle(
                              themeController.currentTheme),
                          onPressed: () {
                            // Get.offAll(() => const MainScreen());
                          },
                          child: CustomWidgets.textWithIconForFullWidth(
                            AppIcons.shareIcon(),
                            "Share",
                          )),
                    ),
                    Gap(16.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          style: AppButtonStyles.mainMenuButtonStyle(
                              themeController.currentTheme),
                          onPressed: () {
                            // Get.offAll(() => const MainScreen());
                          },
                          child: CustomWidgets.textWithIconForFullWidth(
                            AppIcons.downloadIcon(),
                            "Save to Downloads",
                          )),
                    ),
                    Gap(16.h),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                          style: AppButtonStyles.mainMenuButtonStyle(
                              themeController.currentTheme),
                          onPressed: () {
                            Get.offAll(() => const MainScreen());
                          },
                          child: CustomWidgets.textWithIconForFullWidth(
                            AppIcons.homeIcon(),
                            "Back to Home",
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
