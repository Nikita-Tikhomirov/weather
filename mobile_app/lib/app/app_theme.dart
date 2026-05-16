import 'package:flutter/material.dart';

class AppThemeOption {
  const AppThemeOption({
    required this.key,
    required this.name,
    required this.seed,
    required this.scaffold,
    this.brightness = Brightness.light,
  });

  final String key;
  final String name;
  final Color seed;
  final Color scaffold;
  final Brightness brightness;
}

const appThemeOptions = <AppThemeOption>[
  AppThemeOption(
    key: 'ocean',
    name: 'Океан',
    seed: Color(0xFF118AB2),
    scaffold: Color(0xFFF7FAFC),
  ),
  AppThemeOption(
    key: 'mint',
    name: 'Мята',
    seed: Color(0xFF2A9D8F),
    scaffold: Color(0xFFF3FBF8),
  ),
  AppThemeOption(
    key: 'coral',
    name: 'Коралл',
    seed: Color(0xFFE76F51),
    scaffold: Color(0xFFFFF7F4),
  ),
  AppThemeOption(
    key: 'iris',
    name: 'Ирис',
    seed: Color(0xFF6D5BD0),
    scaffold: Color(0xFFF8F7FF),
  ),
  AppThemeOption(
    key: 'forest',
    name: 'Лес',
    seed: Color(0xFF2D6A4F),
    scaffold: Color(0xFFF5FAF6),
  ),
  AppThemeOption(
    key: 'sky_dark',
    name: 'Ночь',
    seed: Color(0xFF60A5FA),
    scaffold: Color(0xFF0F172A),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'graphite',
    name: 'Графит',
    seed: Color(0xFF94A3B8),
    scaffold: Color(0xFF111827),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'plum',
    name: 'Слива',
    seed: Color(0xFFC084FC),
    scaffold: Color(0xFF1E1B2E),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'pine',
    name: 'Хвоя',
    seed: Color(0xFF34D399),
    scaffold: Color(0xFF10201A),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'amber',
    name: 'Янтарь',
    seed: Color(0xFFF59E0B),
    scaffold: Color(0xFF211A10),
    brightness: Brightness.dark,
  ),
];

AppThemeOption themeOptionByKey(String key) {
  return appThemeOptions.firstWhere(
    (option) => option.key == key,
    orElse: () => appThemeOptions.first,
  );
}

ThemeData buildAppTheme(AppThemeOption option) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: option.seed,
    brightness: option.brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: option.scaffold,
    useMaterial3: true,
  );
}
