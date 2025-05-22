import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vision_ai_app/controllers/object_detection_controller.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/main_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/styles/button_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';
import 'package:vision_ai_app/widgets/custom_widgets.dart';

class ChooseImageScreen extends StatelessWidget {
  const ChooseImageScreen({super.key});

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
            "Choose Image",
            style: AppTextStyles.primaryTextStyle70020().copyWith(
              color: themeController.currentTheme.primaryColor,
            ),
          );
        }),
        leading: Obx(() {
          return IconButton(
            icon: AppIcons.backIcon(themeController.currentTheme.primaryColor),
            onPressed: () {
              Get.offAll(() => const MainScreen());
            },
          );
        }),
      ),
      body: Obx(() {
        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: themeController.currentGradient,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: AppPaddings.medium,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Pick Image From",
                        style: AppTextStyles.primaryTextStyle70028().copyWith(
                          color: themeController.currentTheme.primaryColor,
                        ),
                      ),
                      Gap(16.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            style: AppButtonStyles.mainMenuButtonStyle(
                                themeController.currentTheme),
                            onPressed: () =>
                                controller.pickImage(ImageSource.camera),
                            child: CustomWidgets.textWithIconForFullWidth(
                                AppIcons.cameraIcon(), "Camera")),
                      ),
                      Gap(16.h),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: AppButtonStyles.mainMenuButtonStyle(
                              themeController.currentTheme),
                          onPressed: () =>
                              controller.pickImage(ImageSource.gallery),
                          child: CustomWidgets.textWithIconForFullWidth(
                              AppIcons.galleryIcon(), "Gallery"),
                        ),
                      ),
                      Gap(24.h),
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
                          child: controller.selectedImagePath.value.isNotEmpty
                              ? Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.file(
                                        File(
                                            controller.selectedImagePath.value),
                                        fit: BoxFit.cover,
                                        // width: double.infinity,
                                        // height: double.infinity,
                                      ),
                                    ),
                                    // Optional: Add a clear button
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          onPressed: controller.clearImage,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.image_outlined,
                                        size: 48,
                                        color: themeController
                                            .currentTheme.primaryColor,
                                      ),
                                      Gap(8.h),
                                      Text(
                                        "No image selected",
                                        style: AppTextStyles
                                                .primaryTextStyle60016()
                                            .copyWith(
                                          color: themeController
                                              .currentTheme.primaryColor,
                                        ),
                                      ),
                                    ],
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
                            // controller.selectedImagePath.value.isNotEmpty
                            //     ? controller.runObjectDetectionOnSelectedImage
                            //     : null;
                          },
                          child: const Text("Submit"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
