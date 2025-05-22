import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/choose_image_screen.dart';
import 'package:vision_ai_app/screens/real_time_camera_screen.dart';
import 'package:vision_ai_app/screens/theme_list_screen.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/styles/button_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';
import 'package:vision_ai_app/widgets/app_images.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();
    return Scaffold(
      extendBodyBehindAppBar:
          true, // Body behind AppBar for transparency effect
      appBar: AppBar(
        backgroundColor: Colors.transparent, // transparent AppBar
        elevation: 0,
        title: Obx(() {
          return Text(
            "Vision AI",
            style: AppTextStyles.tertiaryTextStyle70020().copyWith(
              color: themeController.currentTheme.primaryColor,
            ),
          );
        }),
        actions: [
          Obx(() {
            return IconButton(
              icon: AppIcons.settingsIcon(
                  themeController.currentTheme.primaryColor),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ThemeListScreen()));
              },
            );
          }),
        ],
      ),
      body: Obx(() {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: themeController.currentGradient,
              ),
              alignment: Alignment.center,
            ),
            SafeArea(
              child: Padding(
                padding: AppPaddings.medium,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        "Spot everything around you using Vision AI",
                        textAlign: TextAlign.center,
                        style: AppTextStyles.primaryTextStyle70040().copyWith(
                          color: themeController.currentTheme.primaryColor,
                        ),
                      ),
                      Padding(
                        padding: AppPaddings.medium,
                        child: Text(
                            "Scan live or choose a photo to get started!",
                            textAlign: TextAlign.center,
                            style:
                                AppTextStyles.primaryTextStyle40016().copyWith(
                              color: themeController.currentTheme.primaryColor,
                            )),
                      ),
                      AppImages.objectDetectionImage(),
                      Padding(
                        padding:
                            AppPaddings.symmetric(horizontal: 12, vertical: 16),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                  style: AppButtonStyles.mainMenuButtonStyle(
                                      themeController.currentTheme),
                                  onPressed: () {
                                    Get.to(const RealTimeCameraScreen());
                                  },
                                  child: const Text('Detect Live')),
                            ),
                            Gap(16.h),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                  style: AppButtonStyles.mainMenuButtonStyle(
                                      themeController.currentTheme),
                                  onPressed: () {
                                    Get.to(const ChooseImageScreen());
                                  },
                                  child: const Text('Detect from Image')),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            )
          ],
        );
      }),
    );
  }
}
