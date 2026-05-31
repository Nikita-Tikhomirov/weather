import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../services/local_db.dart';
import '../../state/task_store.dart';

class HomeVoiceCallHandler {
  HomeVoiceCallHandler({
    required this.store,
    required this.activeConversationKey,
    this.onRecordingChanged,
    this.onShowMessage,
    this.onVoiceSent,
  });

  final TaskStore store;
  final String activeConversationKey;
  final void Function(bool isRecording)? onRecordingChanged;
  final void Function(String message)? onShowMessage;
  final Future<void> Function()? onVoiceSent;

  bool isRecording = false;
  String? voicePath;
  int voiceSec = 0;
  Timer? voiceTimer;

  static const _channel = MethodChannel('family_todo_mobile/voice');

  Future<void> startRecord() async {
    try {
      // Request permission first
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) {
        onShowMessage?.call('Нужен доступ к микрофону');
        return;
      }
      voicePath =
          '${Directory.systemTemp.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _channel.invokeMethod('startRecording', {'path': voicePath});
      isRecording = true;
      voiceSec = 0;
      onRecordingChanged?.call(true);
      voiceTimer?.cancel();
      voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        voiceSec++;
      });
    } catch (e) {
      onShowMessage?.call('Ошибка микрофона: $e');
    }
  }

  Future<void> stopRecord() async {
    if (!isRecording) return;
    voiceTimer?.cancel();
    try {
      await _channel.invokeMethod('stopRecording');
    } catch (_) {
      // stopRecording may fail if recorder wasn't started; safe to ignore
    }
    isRecording = false;
    onRecordingChanged?.call(false);
    if (voicePath == null || voiceSec < 1) {
      onShowMessage?.call('Слишком коротко');
      return;
    }
    await sendVoiceFile();
  }

  Future<void> sendVoiceFile() async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;
    try {
      final bytes = await File(voicePath!).readAsBytes();
      final up = await api.chatUploadSticker(
          actorProfile: actor, bytes: bytes, filename: 'voice.m4a');
      final meta = Map<String, dynamic>.from(up.imageMeta);
      meta['duration_ms'] = voiceSec * 1000;
      final msg = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: activeConversationKey,
        messageType: 'voice',
        text: '🎤 Голосовое',
        imageUrl: up.assetUrl,
        imageMeta: meta,
        clientMessageId: 'v-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.upsertMessages([msg]);
      await onVoiceSent?.call();
      voicePath = null;
    } catch (e) {
      onShowMessage?.call('Ошибка: $e');
    }
  }
}
