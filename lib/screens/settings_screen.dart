import 'package:flutter/material.dart';
import '../core/theme/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;

  const SettingsScreen({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) {
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Тема оформления',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Светлая'),
                value: ThemeMode.light,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Тёмная'),
                value: ThemeMode.dark,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Как в системе'),
                subtitle: const Text(
                  'Следует теме устройства. На Android 12+ подхватывает '
                  'акцентные цвета твоей темы (Material You), если система их отдаёт',
                ),
                value: ThemeMode.system,
                groupValue: themeController.mode,
                onChanged: (v) => themeController.setMode(v!),
              ),
            ],
          );
        },
      ),
    );
  }
}
