import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

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
}
