import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppImages {
  static Widget objectDetectionImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16), // Adjust the radius as needed
      child: Image.asset(
        'assets/images/live.jpg',
        width: 250.w,
        height: 250.h,
        fit: BoxFit.cover,
      ),
    );
  }
} 
