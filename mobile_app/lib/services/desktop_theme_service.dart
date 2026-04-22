import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesktopThemeState {
  const DesktopThemeState({
    required this.mode,
    required this.scheme,
    required this.availableSchemes,
    required this.tokens,
  });

  final String mode;
  final String scheme;
  final List<String> availableSchemes;
  final Map<String, String> tokens;
}

class DesktopThemeService {
  static const Map<String, String> _modeDefaults = {
    'light': 'Ocean',
    'dark': 'Midnight',
  };

  static const Map<String, Map<String, Map<String, String>>> _registry = {
    'light': {
      'Ocean': {
        'bg_app': '#F1F5F9',
        'bg_panel': '#FFFFFF',
        'bg_card': '#F8FAFC',
        'text_primary': '#0F172A',
        'text_muted': '#64748B',
        'border': '#E2E8F0',
        'accent': '#2563EB',
        'accent_hover': '#1D4ED8',
        'success': '#16A34A',
        'success_hover': '#15803D',
        'danger': '#DC2626',
        'danger_hover': '#B91C1C',
        'calendar_chip_bg': '#DBEAFE',
        'calendar_chip_text': '#1E3A8A',
        'selected_nav_bg': '#E2E8F0',
      },
      'Slate': {
        'bg_app': '#EEF2F7',
        'bg_panel': '#FFFFFF',
        'bg_card': '#F6F8FC',
        'text_primary': '#111827',
        'text_muted': '#6B7280',
        'border': '#DCE3EE',
        'accent': '#475569',
        'accent_hover': '#334155',
        'success': '#15803D',
        'success_hover': '#166534',
        'danger': '#DC2626',
        'danger_hover': '#B91C1C',
        'calendar_chip_bg': '#E2E8F0',
        'calendar_chip_text': '#1F2937',
        'selected_nav_bg': '#E2E8F0',
      },
      'Forest': {
        'bg_app': '#ECFDF3',
        'bg_panel': '#FFFFFF',
        'bg_card': '#F3FDF7',
        'text_primary': '#052E16',
        'text_muted': '#3F6A56',
        'border': '#CFE9DA',
        'accent': '#15803D',
        'accent_hover': '#166534',
        'success': '#16A34A',
        'success_hover': '#15803D',
        'danger': '#DC2626',
        'danger_hover': '#B91C1C',
        'calendar_chip_bg': '#DCFCE7',
        'calendar_chip_text': '#166534',
        'selected_nav_bg': '#D1FAE5',
      },
    },
    'dark': {
      'Midnight': {
        'bg_app': '#0B1220',
        'bg_panel': '#111827',
        'bg_card': '#1F2937',
        'text_primary': '#F8FAFC',
        'text_muted': '#94A3B8',
        'border': '#334155',
        'accent': '#3B82F6',
        'accent_hover': '#2563EB',
        'success': '#22C55E',
        'success_hover': '#16A34A',
        'danger': '#F87171',
        'danger_hover': '#EF4444',
        'calendar_chip_bg': '#1E3A8A',
        'calendar_chip_text': '#DBEAFE',
        'selected_nav_bg': '#1E293B',
      },
      'Graphite': {
        'bg_app': '#111111',
        'bg_panel': '#1A1A1A',
        'bg_card': '#242424',
        'text_primary': '#F3F4F6',
        'text_muted': '#A1A1AA',
        'border': '#3F3F46',
        'accent': '#7C8BA1',
        'accent_hover': '#64748B',
        'success': '#4ADE80',
        'success_hover': '#22C55E',
        'danger': '#F87171',
        'danger_hover': '#EF4444',
        'calendar_chip_bg': '#374151',
        'calendar_chip_text': '#E5E7EB',
        'selected_nav_bg': '#2A2A2A',
      },
      'Nord': {
        'bg_app': '#0F172A',
        'bg_panel': '#111827',
        'bg_card': '#1E293B',
        'text_primary': '#E2E8F0',
        'text_muted': '#93C5FD',
        'border': '#334155',
        'accent': '#38BDF8',
        'accent_hover': '#0EA5E9',
        'success': '#34D399',
        'success_hover': '#10B981',
        'danger': '#FB7185',
        'danger_hover': '#F43F5E',
        'calendar_chip_bg': '#0C4A6E',
        'calendar_chip_text': '#BAE6FD',
        'selected_nav_bg': '#172554',
      },
    },
  };

  final ValueNotifier<DesktopThemeState> state =
      ValueNotifier<DesktopThemeState>(
    DesktopThemeState(
      mode: 'light',
      scheme: _modeDefaults['light']!,
      availableSchemes: const ['Ocean', 'Slate', 'Forest'],
      tokens: _registry['light']![_modeDefaults['light']!]!,
    ),
  );

  String? _profile;

  List<String> availableSchemesFor(String mode) =>
      (_registry[mode] ?? const <String, Map<String, String>>{}).keys.toList();

  Future<void> initialize({required String initialProfile}) async {
    _profile = initialProfile;
    await _loadForProfile(initialProfile);
  }

  Future<void> switchProfile(String profile) async {
    _profile = profile;
    await _loadForProfile(profile);
  }

  Future<void> setMode(String mode) async {
    final normalized = _registry.containsKey(mode) ? mode : 'light';
    final schemes = availableSchemesFor(normalized);
    final selected = schemes.contains(state.value.scheme)
        ? state.value.scheme
        : _modeDefaults[normalized] ?? schemes.first;
    _setState(mode: normalized, scheme: selected);
    await _persist();
  }

  Future<void> setScheme(String scheme) async {
    final mode = state.value.mode;
    final schemes = availableSchemesFor(mode);
    if (!schemes.contains(scheme)) {
      return;
    }
    _setState(mode: mode, scheme: scheme);
    await _persist();
  }

  void _setState({required String mode, required String scheme}) {
    final available = availableSchemesFor(mode);
    final fallback = _modeDefaults[mode] ?? available.first;
    final resolvedScheme = available.contains(scheme) ? scheme : fallback;
    final tokens = _registry[mode]![resolvedScheme]!;
    state.value = DesktopThemeState(
      mode: mode,
      scheme: resolvedScheme,
      availableSchemes: available,
      tokens: tokens,
    );
  }

  Future<void> _loadForProfile(String profile) async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_modeKey(profile)) ?? 'light';
    final rawScheme = prefs.getString(_schemeKey(profile));
    final available = availableSchemesFor(mode);
    final scheme = rawScheme != null && available.contains(rawScheme)
        ? rawScheme
        : _modeDefaults[mode] ?? available.first;
    _setState(mode: mode, scheme: scheme);
  }

  Future<void> _persist() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey(profile), state.value.mode);
    await prefs.setString(_schemeKey(profile), state.value.scheme);
  }

  String _modeKey(String profile) => 'desktop_theme_mode_$profile';
  String _schemeKey(String profile) => 'desktop_theme_scheme_$profile';
}

Color colorFromToken(Map<String, String> tokens, String name, Color fallback) {
  final raw = tokens[name];
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  final normalized = raw.startsWith('#') ? raw.substring(1) : raw;
  if (normalized.length != 6) {
    return fallback;
  }
  final value = int.tryParse('FF$normalized', radix: 16);
  if (value == null) {
    return fallback;
  }
  return Color(value);
}
