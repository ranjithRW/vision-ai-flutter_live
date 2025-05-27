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

  static Widget cameraIcon() {
    return Icon(
      Icons.camera_alt_rounded,
      size: 28.h,
    );
  }

  static Widget galleryIcon() {
    return Icon(
      Icons.photo_library_rounded,
      size: 28.h,
    );
  }

  static Widget deleteIcon() {
    return Icon(
      Icons.delete_rounded,
      size: 28.h,
    );
  }

  static Widget shareIcon() {
    return Icon(
      Icons.share_rounded,
      size: 28.h,
    );
  }

  static Widget downloadIcon() {
    return Icon(
      Icons.download_for_offline_rounded,
      size: 28.h,
    );
  }

  static Widget homeIcon() {
    return Icon(
      Icons.home_rounded,
      size: 28.h,
    );
  }

  static Widget snackBarIcon(IconData icon, Color iconColor) {
    return Icon(
      icon,
      color: iconColor,
    );
  }
}
