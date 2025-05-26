import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';

class CustomWidgets {
  static Widget textWithIconForFullWidth(Widget icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        Gap(8.w),
        Text(text),
      ],
    );
  }

  static Widget buildMessageRichText(BuildContext context, String info) {
    const rupeeSymbol = '₹';

    if (!info.contains(rupeeSymbol)) {
      // Fallback to normal text if no rupee symbol found
      return Text(
        info,
        style: AppTextStyles.primaryTextStyle40016(),
      );
    }

    final parts = info.split(rupeeSymbol);
    final afterSymbol = parts.length > 1 ? parts[1] : '';

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
              text: rupeeSymbol, style: AppTextStyles.primaryTextStyle40016()),
          TextSpan(
            text: afterSymbol,
            style: AppTextStyles.primaryTextStyle40016(),
          ),
        ],
      ),
    );
  }
}
