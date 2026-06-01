import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
// ignore_for_file: annotate_overrides

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../contracts/task_data_source.dart';
import '../models/pending_event.dart';
import '../models/chat_models.dart';
import '../models/family_group.dart';
import '../models/task_item.dart';
import '../models/task_project.dart';

part 'local_db_tasks.dart';
part 'local_db_projects.dart';
part 'local_db_chat.dart';

class LocalDb implements TaskDataSource {
  LocalDb._(this._db);

  final Database _db;

  // -- Task CRUD ---------------------------------------------------------

  @override
  Future<void> upsertTask(TaskItem item) async {
    await _db.insert(
      'tasks',
      item.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteTask(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
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

  @override
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

  @override
  Future<void> mergePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    final personal =
        items.where((t) => !t.isFamily && t.ownerKey == ownerKey).toList();
    if (personal.isEmpty) return;
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

  @override
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

  @override
  Future<void> mergeFamilyTasks(List<TaskItem> items) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    if (familyItems.isEmpty) return;
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

  // -- Pending events ----------------------------------------------------

  @override
  Future<void> putPending(PendingEvent event) async {
    await _db.insert(
      'pending_events',
      event.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<PendingEvent>> readPending({int limit = 200}) async {
    final rows = await _db.query(
      'pending_events',
      orderBy: 'happened_at ASC',
      limit: limit,
    );
    return rows.map(PendingEvent.fromDbRow).toList();
  }

  @override
  Future<void> removePending(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    final ph = List.filled(eventIds.length, '?').join(',');
    await _db.delete(
      'pending_events',
      where: 'event_id IN ($ph)',
      whereArgs: eventIds,
    );
  }

  // -- Sync cursor -------------------------------------------------------

  @override
  Future<String> readSince() async {
    final rows = await _db.query(
      'meta',
      where: 'k = ?',
      whereArgs: ['since'],
      limit: 1,
    );
    if (rows.isEmpty) return '1970-01-01T00:00:00';
    return (rows.first['v'] ?? '1970-01-01T00:00:00').toString();
  }

  @override
  Future<void> writeSince(String value) async {
    await _db.insert(
      'meta',
      {'k': 'since', 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<LocalDb> open({String? databasePath}) async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final basePath = await getDatabasesPath();
    final dbPath = databasePath ?? p.join(basePath, 'family_todo_mobile.db');
    final db = await openDatabase(
      dbPath,
      version: 10,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tasks(
            id TEXT PRIMARY KEY,
            owner_key TEXT NOT NULL,
            is_family INTEGER NOT NULL,
            project_id TEXT NOT NULL DEFAULT '',
            group_id TEXT NOT NULL DEFAULT '',
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
            recurrence TEXT NOT NULL DEFAULT '',
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
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
        await _createProjectMessagesTable(db);
        await _createProjectGroupTables(db);
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
        if (oldVersion < 5) {
          await _addColumnIfMissing(
            db,
            'chat_messages',
            'attachments_json',
            "TEXT NOT NULL DEFAULT '[]'",
          );
          await _addColumnIfMissing(
            db,
            'chat_messages',
            'reactions_json',
            "TEXT NOT NULL DEFAULT '[]'",
          );
          await _addColumnIfMissing(db, 'chat_messages', 'my_reaction', 'TEXT');
          await db.delete('chat_messages');
          await db.delete('chat_conversations');
        }
        if (oldVersion < 6) {
          await _createProjectMessagesTable(db);
        }
        if (oldVersion < 7) {
          await _addColumnIfMissing(
            db,
            'chat_conversations',
            'avatar_url',
            "TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 8) {
          await _createProjectGroupTables(db);
          await _addColumnIfMissing(
            db,
            'tasks',
            'project_id',
            "TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 9) {
          await _addColumnIfMissing(
            db,
            'tasks',
            'group_id',
            "TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 10) {
          await _addColumnIfMissing(
            db,
            'tasks',
            'created_at',
            "TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    return LocalDb._(db);
  }

  Future<void> close() => _db.close();

  // ── Shared static helpers ─────────────────────────────────────

  static Future<void> _createProjectGroupTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_projects(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        owner_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS family_groups_local(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        members_json TEXT NOT NULL DEFAULT '[]',
        owner_key TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_family_groups_local(
        project_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        PRIMARY KEY(project_id, group_id)
      );
    ''');
  }

  static Future<void> _createProjectMessagesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_messages(
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        text TEXT NOT NULL,
        data_base64 TEXT,
        mime_type TEXT,
        filename TEXT,
        ts INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_project_messages_project_ts
      ON project_messages(project_id, ts);
    ''');
  }

  static Future<void> _createChatTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_conversations(
        conversation_key TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        members_json TEXT NOT NULL,
        avatar_url TEXT NOT NULL DEFAULT '',
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
        attachments_json TEXT NOT NULL DEFAULT '[]',
        reactions_json TEXT NOT NULL DEFAULT '[]',
        my_reaction TEXT,
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

/// Project/group-related operations exposed as extension methods on [LocalDb].
extension LocalDbProjects on LocalDb {
  Future<void> replaceProjects(List<TaskProject> projects) async {
    await _db.transaction((txn) async {
      await txn.delete('task_projects');
      for (final item in projects) {
        await txn.insert(
          'task_projects',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<TaskProject>> readProjects() async {
    final rows = await _db.query(
      'task_projects',
      orderBy: 'name ASC, id ASC',
    );
    return rows.map(TaskProject.fromDbRow).toList();
  }

  Future<void> upsertProjectLocal(TaskProject project) async {
    await _db.insert(
      'task_projects',
      project.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProjectLocal(String id) async {
    await _db.delete(
      'task_projects',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.delete(
      'project_family_groups_local',
      where: 'project_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> replaceFamilyGroups(
    List<FamilyGroup> groups,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('family_groups_local');
      for (final item in groups) {
        await txn.insert(
          'family_groups_local',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<FamilyGroup>> readFamilyGroups() async {
    final rows = await _db.query(
      'family_groups_local',
      orderBy: 'name ASC, id ASC',
    );
    return rows.map(FamilyGroup.fromDbRow).toList();
  }

  Future<void> upsertFamilyGroupLocal(
    FamilyGroup group,
  ) async {
    await _db.insert(
      'family_groups_local',
      group.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteFamilyGroupLocal(String id) async {
    await _db.delete(
      'family_groups_local',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.delete(
      'project_family_groups_local',
      where: 'group_id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, List<String>>> readProjectGroupMap() async {
    final rows = await _db.query('project_family_groups_local');
    final map = <String, List<String>>{};
    for (final row in rows) {
      final pid = (row['project_id'] ?? '').toString();
      final gid = (row['group_id'] ?? '').toString();
      map.putIfAbsent(pid, () => []);
      map[pid]!.add(gid);
    }
    return map;
  }

  Future<void> replaceProjectGroupMap(
    Map<String, List<String>> map,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete('project_family_groups_local');
      for (final entry in map.entries) {
        for (final gid in entry.value) {
          await txn.insert(
            'project_family_groups_local',
            {
              'project_id': entry.key,
              'group_id': gid,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<void> setProjectGroupsLocal(
    String projectId,
    List<String> groupIds,
  ) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'project_family_groups_local',
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      for (final gid in groupIds) {
        await txn.insert(
          'project_family_groups_local',
          {
            'project_id': projectId,
            'group_id': gid,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}

/// Task operations (convenience alias, delegates to class methods).
/// The actual implementations are in the [LocalDb] class body.
extension LocalDbTasks on LocalDb {
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
    if (personal.isEmpty) return;
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

  Future<void> reconcileFamilyTasks(
    List<TaskItem> items,
  ) async {
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
          await txn.delete(
            'tasks',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    });
  }

  Future<void> mergeFamilyTasks(
    List<TaskItem> items,
  ) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    if (familyItems.isEmpty) return;
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

  Future<List<PendingEvent>> readPending({
    int limit = 200,
  }) async {
    final rows = await _db.query(
      'pending_events',
      orderBy: 'happened_at ASC',
      limit: limit,
    );
    return rows.map(PendingEvent.fromDbRow).toList();
  }

  Future<void> removePending(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
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
    if (rows.isEmpty) return '1970-01-01T00:00:00';
    return (rows.first['v'] ?? '1970-01-01T00:00:00').toString();
  }

  Future<void> writeSince(String value) async {
    await _db.insert(
      'meta',
      {
        'k': 'since',
        'v': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
