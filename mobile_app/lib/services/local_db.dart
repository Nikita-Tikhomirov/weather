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
      version: 9,
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
      },
    );
    return LocalDb._(db);
  }

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

  static List<dynamic> _decodeDynamicList(Object? raw) {
    if (raw == null || raw.toString().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw.toString());
    if (decoded is! List) {
      return const [];
    }
    return decoded;
  }
}
