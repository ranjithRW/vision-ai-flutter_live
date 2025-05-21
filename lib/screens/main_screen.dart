import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/screens/theme_list_screen.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';

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
            Center(
              child: Text(
                'Welcome to Vision AI',
                style: AppTextStyles.primaryTextStyle70024().copyWith(
                  color: themeController.currentTheme.primaryColor,
                ),
              ),
            )
          ],
        );
      }),
    );
  }
}
