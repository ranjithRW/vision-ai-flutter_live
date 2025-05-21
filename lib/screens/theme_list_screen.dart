import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/controllers/theme_controller.dart';
import 'package:vision_ai_app/styles/app_gradients.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';

class ThemeListScreen extends StatelessWidget {
  const ThemeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.find<ThemeController>();

    return Scaffold(
      extendBodyBehindAppBar:
          true, // Body behind AppBar for transparency effect
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: Obx(() {
          return IconButton(
            icon: AppIcons.backIcon(themeController.currentTheme.primaryColor),
            onPressed: () {
              Navigator.pop(context);
            },
          );
        }),
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
                padding: AppPaddings.paddingAll12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick your theme',
                      style: AppTextStyles.primaryTextStyle70024().copyWith(
                        color: themeController.currentTheme.primaryColor,
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: AppPaddings.vertical(12),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final theme = AppGradients.themes[index];
                                  return Padding(
                                    padding: AppPaddings.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(theme.name,
                                          style: AppTextStyles
                                                  .primaryTextStyle50018()
                                              .copyWith(
                                            color: themeController
                                                .currentTheme.primaryColor,
                                          )),
                                      onTap: () =>
                                          themeController.changeTheme(index),
                                      tileColor: Colors.transparent,
                                      leading: AspectRatio(
                                        aspectRatio: 1,
                                        child: Container(
                                          width: 100.w,
                                          height: 100.h,
                                          decoration: BoxDecoration(
                                            gradient: theme.gradient,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                childCount: AppGradients.themes.length,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        );
      }),
    );
  }
}
