import 'package:flutter/foundation.dart';

import '../services/desktop_process_host_service.dart';

/// Desktop-only UI state extracted from [TaskStore].
///
/// Owns theme, voice-host status, and diagnostic log entries so that
/// [TaskStore] stays focused on task-domain concerns.
class DesktopState {
  final ValueNotifier<String> themeMode = ValueNotifier<String>('light');
  final ValueNotifier<String> themeScheme = ValueNotifier<String>('Ocean');
  final ValueNotifier<List<String>> availableSchemes =
      ValueNotifier<List<String>>(const ['Ocean', 'Slate', 'Forest']);
  final ValueNotifier<Map<String, String>> themeTokens =
      ValueNotifier<Map<String, String>>(const <String, String>{});
  final ValueNotifier<DesktopHostState> voiceHostState =
      ValueNotifier<DesktopHostState>(
    const DesktopHostState(
      status: DesktopHostStatus.stopped,
      lastMessage: 'voice stopped',
    ),
  );
  final ValueNotifier<List<String>> logEntries = ValueNotifier<List<String>>(
    const <String>[],
  );

  void setTheme({
    required String mode,
    required String scheme,
    required List<String> schemes,
    required Map<String, String> tokens,
  }) {
    themeMode.value = mode;
    themeScheme.value = scheme;
    availableSchemes.value = List<String>.from(schemes);
    themeTokens.value = Map<String, String>.from(tokens);
  }

  void setVoiceHost(DesktopHostState state) {
    voiceHostState.value = state;
  }

  void appendLog(String entry) {
    final next = List<String>.from(logEntries.value);
    next.add(entry);
    if (next.length > 120) {
      next.removeRange(0, next.length - 120);
    }
    logEntries.value = next;
  }

  void dispose() {
    themeMode.dispose();
    themeScheme.dispose();
    availableSchemes.dispose();
    themeTokens.dispose();
    voiceHostState.dispose();
    logEntries.dispose();
  }
}
