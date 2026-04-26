import 'dart:async';

import 'api_client.dart';

class ChatRealtimeService {
  ChatRealtimeService({
    required this.api,
    required this.actorProfile,
    required this.activeConversationKey,
    required this.onMessagesUpdated,
    this.interval = const Duration(seconds: 2),
  });

  final ApiClient api;
  final String actorProfile;
  final String Function() activeConversationKey;
  final Future<void> Function(String conversationKey) onMessagesUpdated;
  final Duration interval;

  Timer? _timer;
  bool _running = false;
  bool _busy = false;

  void start() {
    if (_running) {
      return;
    }
    _running = true;
    _timer = Timer.periodic(interval, (_) {
      unawaited(tick());
    });
  }

  Future<void> tick() async {
    if (!_running || _busy) {
      return;
    }
    final conversationKey = activeConversationKey().trim();
    if (conversationKey.isEmpty) {
      return;
    }

    _busy = true;
    try {
      await onMessagesUpdated(conversationKey);
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}
