import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/chat_models.dart';
import '../models/chat_snapshots.dart';
import '../services/local_db.dart';
import '../state/task_store.dart';

ChatAttachment buildVoiceAttachment(
  ChatUploadResult upload, {
  required int durationMs,
}) {
  final meta = Map<String, dynamic>.from(upload.imageMeta);
  meta['duration_ms'] = durationMs;
  return ChatAttachment(
    kind: 'voice',
    assetUrl: upload.assetUrl,
    imageMeta: meta,
    sortOrder: 0,
  );
}

/// Standalone voice recording service extracted from _HomePageState.
///
/// Handles microphone permission, recording start/stop, timer,
/// and sending voice files to a chat conversation.
class VoiceRecorderService {
  VoiceRecorderService({
    required this.store,
    this.onRecordingChanged,
    this.onShowSnackBar,
    this.getActiveConversationKey,
    this.onVoiceMessageSent,
  });

  final TaskStore store;
  final void Function(bool recording)? onRecordingChanged;
  final void Function(String message)? onShowSnackBar;
  final String Function()? getActiveConversationKey;
  final FutureOr<void> Function(ChatMessage message)? onVoiceMessageSent;

  static const _channel = MethodChannel('family_todo_mobile/voice');

  String? _voicePath;
  int _voiceSec = 0;
  Timer? _voiceTimer;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  int get voiceSec => _voiceSec;

  Future<void> startRecord() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        onShowSnackBar?.call('Нужен доступ к микрофону');
        return;
      }
      _voicePath =
          '${Directory.systemTemp.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _channel.invokeMethod('startRecording', {'path': _voicePath});
      _isRecording = true;
      _voiceSec = 0;
      onRecordingChanged?.call(true);
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording) {
          _voiceSec++;
          onRecordingChanged?.call(true);
        }
      });
    } catch (e) {
      onShowSnackBar?.call('Ошибка микрофона: $e');
    }
  }

  Future<void> stopRecord() async {
    if (!_isRecording) return;
    _voiceTimer?.cancel();
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (_) {
      // stopRecording may fail if recorder wasn't started; safe to ignore
    }
    _isRecording = false;
    onRecordingChanged?.call(false);
    if (_voicePath == null || _voiceSec < 1) {
      onShowSnackBar?.call('Слишком коротко');
      return;
    }
    await _sendVoiceFile();
  }

  Future<void> _sendVoiceFile() async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;
    final conversationKey = getActiveConversationKey?.call() ?? '';
    try {
      final bytes = await File(_voicePath!).readAsBytes();
      final up = await api.chatUploadSticker(
        actorProfile: actor,
        bytes: bytes,
        filename: 'voice.m4a',
      );
      final attachment = buildVoiceAttachment(
        up,
        durationMs: _voiceSec * 1000,
      );
      final msg = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: 'voice',
        text: '🎤 Голосовое',
        imageUrl: up.assetUrl,
        imageMeta: attachment.imageMeta,
        attachments: [attachment],
        clientMessageId: 'v-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.upsertMessages([msg]);
      await onVoiceMessageSent?.call(msg);
      _voicePath = null;
    } catch (e) {
      onShowSnackBar?.call('Ошибка: $e');
    }
  }

  void dispose() {
    _voiceTimer?.cancel();
  }
}
