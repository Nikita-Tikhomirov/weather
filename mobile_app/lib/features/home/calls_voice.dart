part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Voice recording & call handling extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _CallsVoiceExtension on _HomePageState {
  Future<void> _startRecord(TaskStore store) async {
    const ch = MethodChannel('family_todo_mobile/voice');
    try {
      // Request permission first
      final granted = await ch.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        if (mounted) showSnack('Нужен доступ к микрофону');
        return;
      }
      _voicePath =
          '${Directory.systemTemp.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await ch.invokeMethod('startRecording', {'path': _voicePath});
      _setRecording(true);
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _incrementVoiceSec();
      });
    } catch (e) {
      if (mounted) showSnack('Ошибка микрофона: $e');
    }
  }

  Future<void> _stopRecord(TaskStore store) async {
    if (!_isRecording) return;
    _voiceTimer?.cancel();
    const ch = MethodChannel('family_todo_mobile/voice');
    try {
      await ch.invokeMethod('stopRecording');
    } catch (_) {}
    _stopRecordingState();
    if (_voicePath == null || _voiceSec < 1) {
      if (mounted) showSnack('Слишком коротко');
      return;
    }
    await _sendVoiceFile(store);
  }

  Future<void> _sendVoiceFile(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;
    try {
      final bytes = await File(_voicePath!).readAsBytes();
      final up = await api.chatUploadSticker(
          actorProfile: actor, bytes: bytes, filename: 'voice.m4a');
      final meta = Map<String, dynamic>.from(up.imageMeta);
      meta['duration_ms'] = _voiceSec * 1000;
      final msg = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: _activeConversationKey,
        messageType: 'voice',
        text: '🎤 Голосовое',
        imageUrl: up.assetUrl,
        imageMeta: meta,
        clientMessageId: 'v-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.upsertMessages([msg]);
      await _refreshConversation(store, _activeConversationKey,
          useNetwork: true, quiet: true);
      _voicePath = null;
    } catch (e) {
      if (mounted) showSnack('Ошибка: $e');
    }
  }

  void showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
