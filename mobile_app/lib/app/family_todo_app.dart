import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../features/home/home_page.dart';
import 'app_theme.dart';

class FamilyTodoApp extends StatefulWidget {
  const FamilyTodoApp({super.key});

  @override
  State<FamilyTodoApp> createState() => _FamilyTodoAppState();
}

class _FamilyTodoAppState extends State<FamilyTodoApp> {
  String _themeKey = appThemeOptions.first.key;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_theme_key') ?? _themeKey;
    if (!mounted) {
      return;
    }
    setState(() => _themeKey = themeOptionByKey(saved).key);
  }

  Future<void> _setTheme(String key) async {
    final normalized = themeOptionByKey(key).key;
    setState(() => _themeKey = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_key', normalized);
  }

  @override
  Widget build(BuildContext context) {
    final option = themeOptionByKey(_themeKey);
    return MaterialApp(
      title: 'Задачи',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(option),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
      ],
      locale: const Locale('ru'),
      home: HomePage(
        selectedThemeKey: option.key,
        onThemeChanged: _setTheme,
      ),
    );
  }
}
