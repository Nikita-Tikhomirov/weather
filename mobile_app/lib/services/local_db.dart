import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/pending_event.dart';
import '../models/chat_models.dart';
import '../models/task_item.dart';

class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final basePath = await getDatabasesPath();
    final dbPath = p.join(basePath, 'family_todo_mobile.db');
    final db = await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tasks(
            id TEXT PRIMARY KEY,
            owner_key TEXT NOT NULL,
            is_family INTEGER NOT NULL,
            title TEXT NOT NULL,
            details TEXT NOT NULL,
            due_date TEXT NOT NULL,
            time TEXT NOT NULL,
            workflow_status TEXT NOT NULL,
            priority TEXT NOT NULL,
            tags_json TEXT NOT NULL,
            participants_json TEXT NOT NULL,
            reminder_offsets_json TEXT NOT NULL DEFAULT '[]',
            duration_minutes INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            version INTEGER NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE pending_events(
            event_id TEXT PRIMARY KEY,
            entity TEXT NOT NULL,
            action TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            happened_at TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE meta(
            k TEXT PRIMARY KEY,
            v TEXT NOT NULL
          );
        ''');
        await _createChatTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN reminder_offsets_json TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 3) {
          await _createChatTables(db);
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(db, 'chat_messages', 'edited_at', 'TEXT');
          await _addColumnIfMissing(db, 'chat_messages', 'deleted_at', 'TEXT');
        }
      },
    );
    return LocalDb._(db);
  }

  Future<void> upsertTask(TaskItem item) async {
    await _db.insert(
      'tasks',
      item.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTask(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceTasks(List<TaskItem> items) async {
    await _db.transaction((txn) async {
      await txn.delete('tasks');
      for (final item in items) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> replacePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'tasks',
        where: 'is_family = 0 AND owner_key = ?',
        whereArgs: [ownerKey],
      );
      for (final item in items.where((t) => !t.isFamily)) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> mergePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    final personal =
        items.where((t) => !t.isFamily && t.ownerKey == ownerKey).toList();
    if (personal.isEmpty) {
      return;
    }
    await _db.transaction((txn) async {
      for (final item in personal) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> reconcileFamilyTasks(List<TaskItem> items) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    await _db.transaction((txn) async {
      for (final item in familyItems) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final rows = await txn.query(
        'tasks',
        columns: const ['id'],
        where: 'is_family = 1',
      );
      final remoteIds = familyItems.map((item) => item.id).toSet();
      for (final row in rows) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty && !remoteIds.contains(id)) {
          await txn.delete('tasks', where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  Future<void> mergeFamilyTasks(List<TaskItem> items) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    if (familyItems.isEmpty) {
      return;
    }
    await _db.transaction((txn) async {
      for (final item in familyItems) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<TaskItem>> readTasks({
    String? ownerKey,
    bool includeAll = false,
  }) async {
    final rows = await _db.query(
      'tasks',
      where: includeAll || ownerKey == null
          ? null
          : '(owner_key = ? OR is_family = 1)',
      whereArgs: includeAll || ownerKey == null ? null : [ownerKey],
      orderBy: 'updated_at DESC',
    );
    return rows.map(TaskItem.fromDbRow).toList();
  }

  Future<void> putPending(PendingEvent event) async {
    await _db.insert(
      'pending_events',
      event.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingEvent>> readPending({int limit = 200}) async {
    final rows = await _db.query(
      'pending_events',
      orderBy: 'happened_at ASC',
      limit: limit,
    );
    return rows.map(PendingEvent.fromDbRow).toList();
  }

  Future<void> removePending(List<String> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }
    final placeholders = List.filled(eventIds.length, '?').join(',');
    await _db.delete(
      'pending_events',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );
  }

  Future<String> readSince() async {
    final rows = await _db.query(
      'meta',
      where: 'k = ?',
      whereArgs: ['since'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return '1970-01-01T00:00:00';
    }
    return (rows.first['v'] ?? '1970-01-01T00:00:00').toString();
  }

  Future<void> writeSince(String value) async {
    await _db.insert(
        'meta',
        {
          'k': 'since',
          'v': value,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertConversation(ChatConversation item) async {
    await _db.insert(
      'chat_conversations',
      {
        'conversation_key': item.conversationKey,
        'kind': item.kind,
        'title': item.title,
        'members_json': jsonEncode(item.members),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> upsertMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) {
      return;
    }
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
      'chat_meta',
      {'k': 'cursor:$conversationKey', 'v': cursor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> readChatCursor(String conversationKey) async {
    final rows = await _db.query(
      'chat_meta',
      where: 'k = ?',
      whereArgs: ['cursor:$conversationKey'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['v']?.toString();
  }

  static Future<void> _createChatTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_conversations(
        conversation_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        members_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages(
        id TEXT PRIMARY KEY,
        conversation_key TEXT NOT NULL,
        sender_profile TEXT NOT NULL,
        message_type TEXT NOT NULL,
        text TEXT NOT NULL,
        sticker_id TEXT,
        image_url TEXT,
        image_meta_json TEXT NOT NULL DEFAULT '{}',
        client_message_id TEXT,
        created_at TEXT NOT NULL,
        edited_at TEXT,
        deleted_at TEXT
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_created
      ON chat_messages(conversation_key, created_at);
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_stickers(
        sticker_id TEXT PRIMARY KEY,
        pack_key TEXT NOT NULL,
        title TEXT NOT NULL,
        asset_url TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_outbox(
        client_message_id TEXT PRIMARY KEY,
        conversation_key TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_meta(
        k TEXT PRIMARY KEY,
        v TEXT NOT NULL
      );
    ''');
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  static List<String> _decodeStringList(String raw) {
    if (raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded.map((item) => item.toString()).toList();
  }

  static Map<String, dynamic> _decodeMap(String raw) {
    if (raw.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const {};
    }
    return decoded.cast<String, dynamic>();
  }
}
