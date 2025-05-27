import 'package:flutter/material.dart';
import 'package:vision_ai_app/styles/app_colors.dart';
import 'package:vision_ai_app/styles/app_gradients.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';

class AppButtonStyles {
  static ButtonStyle? mainMenuButtonStyle(GradientTheme theme,
      {bool isEnabled = true}) {
    return ElevatedButton.styleFrom(
      backgroundColor:
          isEnabled ? theme.primaryColor : AppColors.disabledBackgroundColor,
      foregroundColor:
          isEnabled ? theme.tertiaryColor : AppColors.disabledTextColor,
      textStyle: AppTextStyles.primaryTextStyle60016()
          .copyWith(color: theme.tertiaryColor, inherit: true),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  static ButtonStyle? themeSetButtonStyle(
      GradientTheme currentTheme, GradientTheme itemTheme) {
    return ElevatedButton.styleFrom(
      backgroundColor: currentTheme == itemTheme
          ? AppColors.disabledBackgroundColor
          : currentTheme.primaryColor,
      foregroundColor: currentTheme == itemTheme
          ? AppColors.disabledTextColor
          : currentTheme.tertiaryColor,
      textStyle: AppTextStyles.primaryTextStyle80016()
          .copyWith(color: currentTheme.tertiaryColor, inherit: true),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
