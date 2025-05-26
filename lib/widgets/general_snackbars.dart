import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:get/get.dart';
import 'package:vision_ai_app/styles/app_paddings.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';
import 'package:vision_ai_app/styles/general_box_shadows.dart';
import 'package:vision_ai_app/widgets/app_icons.dart';
import 'package:vision_ai_app/widgets/custom_widgets.dart';

class GeneralSnackbars {
  static void showSnackBarAtTop(
      BuildContext context, String title, String info, String type) {
    IconData icon = Icons.info;
    Color iconColor = Colors.black;

    switch (type.toUpperCase()) {
      case "SUCCESS":
        icon = Icons.check_circle_rounded;
        iconColor = Colors.green;
        break;
      case "ERROR":
        icon = Icons.error;
        iconColor = Colors.red;
        break;
      case "INFO":
        icon = Icons.info;
        iconColor = Colors.blue;
        break;
    }

    Get.rawSnackbar(
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      margin: AppPaddings.medium,
      borderRadius: 8,
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 5),
      isDismissible: true,
      messageText: Dismissible(
        key: UniqueKey(),
        direction: DismissDirection.horizontal, // Allow swiping left and right
        onDismissed: (_) => Get.back(), // Dismiss snackbar
        child: Container(
          padding: AppPaddings.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [GeneralBoxShadows.elevationBoxShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Row(
                  children: [
                    AppIcons.snackBarIcon(context, icon, iconColor),
                    Gap(8.w),
                    Flexible(
                      child: Text(title,
                          style: AppTextStyles.primaryTextStyle70018()),
                    ),
                  ],
                ),
              if (info.isNotEmpty)
                Padding(
                  padding: AppPaddings.only(top: 8),
                  child: CustomWidgets.buildMessageRichText(context, info),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void showSnackBarAtBottom(
      BuildContext context, String title, String info, String type) {
    IconData icon = Icons.info;
    Color iconColor = Colors.black;

    switch (type.toUpperCase()) {
      case "SUCCESS":
        icon = Icons.check_circle_rounded;
        iconColor = Colors.green;
        break;
      case "ERROR":
        icon = Icons.error;
        iconColor = Colors.red;
        break;
      case "INFO":
        icon = Icons.info;
        iconColor = Colors.blue;
        break;
    }

    Get.rawSnackbar(
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.transparent,
      margin: AppPaddings.medium,
      borderRadius: 8,
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 5),
      isDismissible: true,
      messageText: Dismissible(
        key: UniqueKey(),
        direction: DismissDirection.horizontal, // Allow swiping left and right
        onDismissed: (_) => Get.back(), // Dismiss snackbar
        child: Container(
          padding: AppPaddings.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [GeneralBoxShadows.elevationBoxShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Row(
                  children: [
                    AppIcons.snackBarIcon(context, icon, iconColor),
                    Gap(8.w),
                    Flexible(
                      child: Text(
                        title,
                        style: AppTextStyles.primaryTextStyle70018(),
                      ),
                    ),
                  ],
                ),
              if (info.isNotEmpty)
                Padding(
                  padding: AppPaddings.only(top: 8),
                  child: CustomWidgets.buildMessageRichText(context, info),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
