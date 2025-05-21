import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:vision_ai_app/styles/app_gradients.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends GetxController {
  RxInt selectedIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    loadTheme().then((index) {
      if (index != null && index >= 0 && index < AppGradients.themes.length) {
        selectedIndex.value = index;
      }
    });
  }

  Gradient get currentGradient =>
      AppGradients.themes[selectedIndex.value].gradient;

  GradientTheme get currentTheme => AppGradients.themes[selectedIndex.value];

  void changeTheme(int index) {
    selectedIndex.value = index;
    saveTheme(index);
  }

  Future<void> saveTheme(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_index', index);
  }

  Future<int?> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('theme_index');
  }
}
