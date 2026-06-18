import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/project_contact.dart';
import '../../models/project_file.dart';
import '../../services/api_client.dart';
import '../../services/local_db.dart';
import '../../services/project_access.dart';
import '../../services/project_bridge_service.dart';
import '../../state/task_store.dart';
import 'home_helpers.dart';

/// Standalone manager that encapsulates all project/group/file logic
/// previously defined as an extension on `_HomePageState`.
///
/// The owning widget reads mutable fields after calling methods and
/// is responsible for calling `setState` (or equivalent) to rebuild.
class HomeProjectsDataManager {
  HomeProjectsDataManager({
    required this.store,
    required this.api,
    required this.owner,
    this.currentProfilePhone = '',
    this.projectChatsUnavailableMessage = 'Project chats are unavailable',
    List<String>? projectConfigPaths,
    this.onShowFileContentViewer,
    this.onShowError,
  }) : projectConfigPaths = List.unmodifiable(
          projectConfigPaths ?? _defaultProjectConfigPaths(),
        );

  final TaskStore store;
  final ApiClient api;
  final String owner;

  /// The current profile phone – used by [canUseProjectChats].
  String currentProfilePhone;
  final String projectChatsUnavailableMessage;
  final List<String> projectConfigPaths;

  // ── Mutable state (watched by the UI) ────────────────────────

  List<ProjectContact> projectContacts = const <ProjectContact>[];
  ProjectBridgeService? projectBridge;
  final List<BridgeMessage> projectMessages = <BridgeMessage>[];
  List<ProjectFileNode> projectFiles = const <ProjectFileNode>[];
  String projectFileTreePath = '';
  bool projectFilesLoading = false;

  String? activeProjectSessionId;
  final Map<String, String> projectSessionIds = <String, String>{};

  /// The currently-active conversation key (read/written by owner).
  String activeConversationKey = '';

  // ── File-content pending state ───────────────────────────────

  ValueNotifier<String>? pendingFileContent;
  String? pendingFilePath;

  // ── Callbacks for UI actions that require a BuildContext ─────

  /// Called when a file-content message should be displayed.
  void Function(BridgeMessage msg)? onShowFileContentViewer;

  /// Called when a transient error should be shown as a snackbar.
  void Function(String message)? onShowError;

  // ─────────────────────────────────────────────────────────────
  // Public API — mirrors the original _ProjectsDataExtension
  // ─────────────────────────────────────────────────────────────

  void loadProjects() {
    if (!canUseProjectChats(currentProfilePhone)) {
      projectContacts = const <ProjectContact>[];
      return;
    }
    try {
      final normalized = projectConfigPaths
          .map((p) => p.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/'))
          .toList();

      File? file;
      for (final path in normalized) {
        final f = File(path);
        if (f.existsSync()) {
          file = f;
          break;
        }
      }

      if (file == null) {
        projectContacts = fallbackProjects();
        return;
      }

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final rawList = json['projects'] as List<dynamic>? ?? [];
      final projects = rawList
          .whereType<Map<String, dynamic>>()
          .map(ProjectContact.fromJson)
          .toList();
      projectContacts = projects;
    } catch (_) {
      projectContacts = fallbackProjects();
    }
  }

  List<ProjectContact> fallbackProjects() {
    return const <ProjectContact>[];
  }

  Future<void> openProjectContact(
    ProjectContact project,
  ) async {
    if (!canUseProjectChats(currentProfilePhone)) {
      onShowError?.call(projectChatsUnavailableMessage);
      return;
    }

    final db = store.repository.db;
    final projectId = project.id;

    // Set active conversation to project key
    activeConversationKey = project.conversationKey;

    // Restore saved session id for this project
    final savedSessionId = await loadProjectSessionId(projectId);
    activeProjectSessionId = savedSessionId;

    // Load persisted messages from database
    final savedRows =
        await db.loadProjectMessages(projectId: projectId, limit: 300);
    final restoredMessages = savedRows.map((row) {
      return BridgeMessage(
        type: (row['type'] ?? '').toString(),
        text: (row['text'] ?? '').toString(),
        projectId: (row['project_id'] ?? '').toString(),
        sessionId: (row['session_id'] ?? '').toString(),
        imageBase64: (row['data_base64'] ?? '').toString(),
        imageMimeType: (row['mime_type'] ?? '').toString(),
        imageFilename: (row['filename'] ?? '').toString(),
      );
    }).toList();

    projectMessages
      ..clear()
      ..addAll(restoredMessages);

    // Only dispose existing bridge if connecting to a different project
    if (projectBridge != null && projectBridge!.activeProjectId != projectId) {
      projectBridge?.dispose();
      projectBridge = null;
    }
    // If bridge already connected to this project, just reuse it
    if (projectBridge != null && projectBridge!.isConnected) {
      return;
    }

    // Connect to the remote bridge server running on PC
    final bridge = ProjectBridgeService(
      onMessage: (msg) {
        if (msg.isHistory) {
          // History replay: only add messages we don't already have
          final existingTexts = projectMessages.map((m) => m.text).toSet();
          final newMsgs = msg.messages
              .where((m) => !existingTexts.contains(m.text))
              .toList();
          if (newMsgs.isNotEmpty) {
            projectMessages.addAll(newMsgs);
          }
          return;
        }
        if (msg.isOutput && msg.streamId.isNotEmpty) {
          applyStreamingProjectOutput(db, msg);
          return;
        }
        // Persist incoming non-stream message to database.
        saveProjectMessageToDb(db, msg);
        if (msg.isSessionInfo && msg.sessionId.isNotEmpty) {
          activeProjectSessionId = msg.sessionId;
          saveProjectSessionId(projectId, msg.sessionId);
          if (projectBridge != null) {
            projectBridge!.currentSessionId = msg.sessionId;
          }
        }
        if (msg.isProjects && msg.projects.isNotEmpty) {
          projectContacts = msg.projects.map(ProjectContact.fromJson).toList();
        }
        if (msg.isFiles) {
          projectFiles = msg.files;
          projectFilesLoading = false;
        }
        if (msg.isFileContent) {
          projectMessages.add(msg);
          onFileContentArrived(msg);
          onShowFileContentViewer?.call(msg);
          return;
        }
        projectMessages.add(msg);
      },
      onStatusChange: (connected, status) {
        projectMessages.add(BridgeMessage(type: 'status', text: status));
      },
    );

    projectBridge = bridge;

    bridge.startProject(project, resumeSessionId: savedSessionId);
    final ok = await bridge.connect();
    if (!ok) return;
  }

  void applyStreamingProjectOutput(LocalDb db, BridgeMessage msg) {
    var handled = false;
    final lastIndex = projectMessages.lastIndexWhere(
      (item) => item.isOutput && item.streamId == msg.streamId,
    );
    if (lastIndex >= 0) {
      final current = projectMessages[lastIndex];
      projectMessages[lastIndex] = msg.isFinal
          ? msg.copyWith(append: false)
          : current.copyWith(text: current.text + msg.text);
      handled = true;
    } else {
      projectMessages.add(msg);
      handled = true;
    }
    if (handled && msg.isFinal) {
      saveProjectMessageToDb(db, msg.copyWith(append: false));
    }
  }

  ProjectContact? projectByConversationKey(String key) {
    if (!isProjectConversation(key)) {
      return null;
    }
    return projectContacts.cast<ProjectContact?>().firstWhere(
          (p) => p?.conversationKey == key,
          orElse: () => null,
        );
  }

  // ── Project session persistence helpers ─────────────────────

  void saveProjectMessageToDb(LocalDb db, BridgeMessage msg) {
    final projectId = msg.projectId.isNotEmpty
        ? msg.projectId
        : projectByConversationKey(activeConversationKey)?.id ?? '';
    if (projectId.isEmpty) return;
    final sessionId = msg.sessionId.isNotEmpty
        ? msg.sessionId
        : (activeProjectSessionId ?? '');
    final id =
        '${msg.type}_${msg.text.hashCode}_${DateTime.now().microsecondsSinceEpoch}';
    db.saveProjectMessage(
      id: id,
      projectId: projectId,
      sessionId: sessionId,
      type: msg.type,
      text: msg.text,
      dataBase64: msg.imageBase64.isNotEmpty ? msg.imageBase64 : null,
      mimeType: msg.imageMimeType.isNotEmpty ? msg.imageMimeType : null,
      filename: msg.imageFilename.isNotEmpty ? msg.imageFilename : null,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String?> loadProjectSessionId(String projectId) async {
    if (projectSessionIds.containsKey(projectId)) {
      return projectSessionIds[projectId];
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('project_session_$projectId');
    if (saved != null && saved.isNotEmpty) {
      projectSessionIds[projectId] = saved;
      return saved;
    }
    return null;
  }

  Future<void> saveProjectSessionId(
    String projectId,
    String sessionId,
  ) async {
    projectSessionIds[projectId] = sessionId;
    final prefs = await SharedPreferences.getInstance();
    if (sessionId.isEmpty) {
      await prefs.remove('project_session_$projectId');
    } else {
      await prefs.setString('project_session_$projectId', sessionId);
    }
  }

  // ── File-content helpers ────────────────────────────────────

  /// Called when a file_content message arrives from the bridge.
  void onFileContentArrived(BridgeMessage msg) {
    if (pendingFileContent == null) return;
    final path = msg.filePath.isNotEmpty ? msg.filePath : msg.projectId;
    if (path == pendingFilePath || msg.fileContentText.isNotEmpty) {
      pendingFileContent!.value = msg.fileContentText;
    }
  }
}

List<String> _defaultProjectConfigPaths() {
  return [
    'family_data/nik/projects.json',
    '../family_data/nik/projects.json',
    '${Directory.current.path}/family_data/nik/projects.json',
    '${Directory.current.parent.path}/family_data/nik/projects.json',
  ];
}
