import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppPaddings {
  // All sides
  static EdgeInsets all(double value) => EdgeInsets.all(value.w);

  // Symmetric: vertical & horizontal
  static EdgeInsets symmetric({double vertical = 0, double horizontal = 0}) =>
      EdgeInsets.symmetric(
        vertical: vertical.h,
        horizontal: horizontal.w,
      );

  // Only specific sides
  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      EdgeInsets.only(
        left: left.w,
        top: top.h,
        right: right.w,
        bottom: bottom.h,
      );

  // Shortcut methods
  static EdgeInsets horizontal(double value) =>
      EdgeInsets.symmetric(horizontal: value.w);
  static EdgeInsets vertical(double value) =>
      EdgeInsets.symmetric(vertical: value.h);

  // Common presets
  static EdgeInsets get small => all(8);
  static EdgeInsets get paddingAll12 => all(12);
  static EdgeInsets get medium => all(16);
  static EdgeInsets get large => all(24);
}
