part of 'local_db.dart';

List<String> _decodeStringList(String raw) {
  if (raw.isEmpty || raw == '[]') return [];
  try {
    return (jsonDecode(raw) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

Map<String, dynamic>? _decodeMap(String raw) {
  if (raw.isEmpty || raw == '{}') return null;
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

List<dynamic> _decodeDynamicList(String raw) {
  if (raw.isEmpty || raw == '[]') return [];
  try {
    return jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    return [];
  }
}

/// Chat-related operations exposed as extension methods on [LocalDb].
extension LocalDbChat on LocalDb {
  Future<void> upsertConversation(ChatConversation item) async {
    await _db.insert(
      'chat_conversations',
      {
        'conversation_key': item.conversationKey,
        'kind': item.kind,
        'title': item.title,
        'members_json': jsonEncode(item.members),
        'avatar_url': item.avatarUrl ?? '',
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> replaceConversations(List<ChatConversation> items) async {
    final keys = items.map((item) => item.conversationKey).toSet().toList();
    await _db.transaction((txn) async {
      if (keys.isEmpty) {
        await txn.delete('chat_messages');
        await txn.delete('chat_conversations');
      } else {
        final placeholders = List.filled(keys.length, '?').join(',');
        await txn.delete(
          'chat_messages',
          where: 'conversation_key NOT IN ($placeholders)',
          whereArgs: keys,
        );
        await txn.delete(
          'chat_conversations',
          where: 'conversation_key NOT IN ($placeholders)',
          whereArgs: keys,
        );
      }
      for (final item in items) {
        await txn.insert(
          'chat_conversations',
          {
            'conversation_key': item.conversationKey,
            'kind': item.kind,
            'title': item.title,
            'members_json': jsonEncode(item.members),
            'avatar_url': item.avatarUrl ?? '',
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ChatConversation>> readConversations() async {
    final rows = await _db.query(
      'chat_conversations',
      orderBy: 'updated_at DESC, conversation_key ASC',
    );
    return rows.map((row) {
      final payload = Map<String, dynamic>.from(row);
      payload['members'] =
          _decodeStringList((row['members_json'] ?? '').toString());
      return ChatConversation.fromJson(payload);
    }).toList();
  }

  Future<void> deleteConversation(String conversationKey) async {
    final key = conversationKey.trim();
    if (key.isEmpty) return;
    await _db.transaction((txn) async {
      await txn.delete(
        'chat_messages',
        where: 'conversation_key = ?',
        whereArgs: [key],
      );
      await txn.delete(
        'chat_conversations',
        where: 'conversation_key = ?',
        whereArgs: [key],
      );
    });
  }

  Future<void> upsertMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    await _db.transaction((txn) async {
      for (final item in messages) {
        await txn.insert(
          'chat_messages',
          {
            'id': item.id,
            'conversation_key': item.conversationKey,
            'sender_profile': item.senderProfile,
            'message_type': item.messageType,
            'text': item.text,
            'sticker_id': item.stickerId,
            'image_url': item.imageUrl,
            'image_meta_json': jsonEncode(item.imageMeta),
            'attachments_json': jsonEncode(
              item.attachments.map((a) => a.toJson()).toList(),
            ),
            'reactions_json': jsonEncode(
              item.reactions.map((r) => r.toJson()).toList(),
            ),
            'my_reaction': item.myReaction,
            'client_message_id': item.clientMessageId,
            'created_at': item.createdAt,
            'edited_at': item.editedAt,
            'deleted_at': item.deletedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<ChatMessage>> readMessages({
    required String conversationKey,
    int limit = 100,
  }) async {
    final rows = await _db.query(
      'chat_messages',
      where: 'conversation_key = ?',
      whereArgs: [conversationKey],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.reversed.map((row) {
      final payload = Map<String, dynamic>.from(row);
      payload['image_meta'] =
          _decodeMap((row['image_meta_json'] ?? '').toString());
      payload['attachments'] =
          _decodeDynamicList((row['attachments_json'] ?? '[]').toString());
      payload['reactions'] =
          _decodeDynamicList((row['reactions_json'] ?? '[]').toString());
      payload['my_reaction'] = row['my_reaction'];
      return ChatMessage.fromJson(payload);
    }).toList();
  }

  Future<void> replaceStickerPacks(List<StickerPack> packs) async {
    await _db.transaction((txn) async {
      await txn.delete('chat_stickers');
      for (final pack in packs) {
        for (final item in pack.items) {
          await txn.insert(
            'chat_stickers',
            {
              'sticker_id': item.stickerId,
              'pack_key': pack.packKey,
              'title': item.title,
              'asset_url': item.assetUrl,
              'sort_order': item.sortOrder,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<List<StickerPack>> readStickerPacks() async {
    final rows = await _db.query(
      'chat_stickers',
      orderBy: 'pack_key ASC, sort_order ASC, sticker_id ASC',
    );
    final grouped = <String, List<StickerItem>>{};
    for (final row in rows) {
      final packKey = (row['pack_key'] ?? '').toString();
      grouped.putIfAbsent(packKey, () => []);
      grouped[packKey]!.add(
        StickerItem.fromJson(Map<String, dynamic>.from(row)),
      );
    }
    return grouped.entries
        .map(
          (entry) => StickerPack(
            packKey: entry.key,
            title: entry.key,
            items: entry.value,
          ),
        )
        .toList();
  }

  Future<void> saveChatCursor({
    required String conversationKey,
    required String cursor,
  }) async {
    await _db.insert(
      'meta',
      {'k': 'chat_cursor_$conversationKey', 'v': cursor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readChatCursor({
    required String conversationKey,
  }) async {
    final rows = await _db.query(
      'meta',
      where: 'k = ?',
      whereArgs: ['chat_cursor_$conversationKey'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['v'] as String?;
  }

  Future<void> saveProjectMessage({
    required String id,
    required String projectId,
    required String sessionId,
    required String type,
    required String text,
    String? dataBase64,
    String? mimeType,
    String? filename,
    required int ts,
  }) async {
    await _db.insert(
      'project_messages',
      {
        'id': id,
        'project_id': projectId,
        'session_id': sessionId,
        'type': type,
        'text': text,
        'data_base64': dataBase64,
        'mime_type': mimeType,
        'filename': filename,
        'ts': ts,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> loadProjectMessages({
    required String projectId,
    int limit = 300,
  }) async {
    final rows = await _db.query(
      'project_messages',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'ts ASC, id ASC',
      limit: limit,
    );
    return rows;
  }

  Future<void> clearProjectMessages(String projectId) async {
    await _db.delete(
      'project_messages',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
  }
}
