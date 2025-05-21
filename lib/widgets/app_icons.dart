import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppIcons {
  static Widget settingsIcon(Color? color) {
    return Icon(
      Icons.settings_rounded,
      size: 28.h,
      color: color,
    );
  }

  static Widget backIcon(Color? color) {
    return Icon(
      Icons.arrow_back_ios_new_rounded,
      size: 28.h,
      color: color,
    );
  }
}
