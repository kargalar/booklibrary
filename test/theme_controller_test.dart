import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:booklibrary/app/theme_controller.dart';

void main() {
  test('theme preference is restored and persisted', () async {
    SharedPreferences.setMockInitialValues({'theme.mode': 'dark'});
    final controller = ThemeController();

    await controller.load();
    expect(controller.value, ThemeMode.dark);

    controller.toggle();
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(controller.value, ThemeMode.light);
    expect(prefs.getString('theme.mode'), 'light');
    controller.dispose();
  });
}
