import 'package:flutter/material.dart';
import 'package:vision_ai_app/styles/app_gradients.dart';
import 'package:vision_ai_app/styles/app_text_styles.dart';

class AppButtonStyles {
  static ButtonStyle? mainMenuButtonStyle(GradientTheme theme) {
    return ElevatedButton.styleFrom(
      backgroundColor: theme.primaryColor,
      foregroundColor: theme.tertiaryColor,
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
      backgroundColor:
          currentTheme == itemTheme ? Colors.grey : currentTheme.primaryColor,
      foregroundColor:
          currentTheme == itemTheme ? Colors.grey : currentTheme.tertiaryColor,
      textStyle: AppTextStyles.primaryTextStyle60016()
          .copyWith(color: currentTheme.tertiaryColor, inherit: true),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
