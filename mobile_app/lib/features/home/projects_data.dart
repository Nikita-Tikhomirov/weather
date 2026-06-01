part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Project data & bridge helpers extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _ProjectsDataExtension on _HomePageState {
  Future<void> _openProjectContact(
    TaskStore store,
    ProjectContact project,
  ) async {
    if (!canUseProjectChats(_currentProfilePhone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Проектные чаты недоступны')),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final db = store.repository.db;
    final projectId = project.id;

    // Set active conversation to project key
    _setActiveConversation(project.conversationKey);

    // Restore saved session id for this project
    final savedSessionId = await _loadProjectSessionId(projectId);
    _activeProjectSessionId = savedSessionId;

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

    _setProjectMessagesList(restoredMessages);

    // Only dispose existing bridge if connecting to a different project
    if (_projectBridge != null &&
        _projectBridge!.activeProjectId != projectId) {
      _projectBridge?.dispose();
      _projectBridge = null;
    }
    // If bridge already connected to this project, just reuse it
    if (_projectBridge != null && _projectBridge!.isConnected) {
      return;
    }

    // Connect to the remote bridge server running on PC
    final bridge = ProjectBridgeService(
      onMessage: (msg) {
        if (mounted) {
          if (msg.isHistory) {
            // History replay: only add messages we don't already have
            final existingTexts = _projectMessages.map((m) => m.text).toSet();
            final newMsgs = msg.messages
                .where((m) => !existingTexts.contains(m.text))
                .toList();
            if (newMsgs.isNotEmpty) {
              _addProjectMessages(newMsgs);
            }
            return;
          }
          if (msg.isOutput && msg.streamId.isNotEmpty) {
            _applyStreamingProjectOutput(db, msg);
            return;
          }
          // Persist incoming non-stream message to database.
          _saveProjectMessageToDb(db, msg);
          if (msg.isSessionInfo && msg.sessionId.isNotEmpty) {
            _activeProjectSessionId = msg.sessionId;
            _saveProjectSessionId(projectId, msg.sessionId);
            if (_projectBridge != null) {
              _projectBridge!.currentSessionId = msg.sessionId;
            }
          }
          if (msg.isProjects && msg.projects.isNotEmpty) {
            _setProjectContacts(
              msg.projects.map(ProjectContact.fromJson).toList(),
            );
          }
          if (msg.isFiles) {
            _setProjectFiles(msg.files);
          }
          if (msg.isFileContent) {
            _addProjectMessage(msg);
            _onFileContentArrived(msg);
            if (mounted) {
              _showFileContentViewer(msg);
            }
            return;
          }
          _addProjectMessage(msg);
        }
      },
      onStatusChange: (connected, status) {
        if (mounted) {
          _addProjectMessage(BridgeMessage(type: 'status', text: status));
        }
      },
    );

    _setProjectBridge(bridge);

    bridge.startProject(project, resumeSessionId: savedSessionId);
    final ok = await bridge.connect();
    if (!ok) return;
  }

  // ignore: invalid_use_of_protected_member
  void _applyStreamingProjectOutput(LocalDb db, BridgeMessage msg) {
    var handled = false;
    // ignore: invalid_use_of_protected_member
    setState(() {
      final lastIndex = _projectMessages.lastIndexWhere(
        (item) => item.isOutput && item.streamId == msg.streamId,
      );
      if (lastIndex >= 0) {
        final current = _projectMessages[lastIndex];
        _projectMessages[lastIndex] = msg.isFinal
            ? msg.copyWith(append: false)
            : current.copyWith(text: current.text + msg.text);
        handled = true;
      } else {
        _projectMessages.add(msg);
        handled = true;
      }
    });
    if (handled && msg.isFinal) {
      _saveProjectMessageToDb(db, msg.copyWith(append: false));
    }
  }

  ProjectContact? _projectByConversationKey(String key) {
    if (!isProjectConversation(key)) {
      return null;
    }
    return _projectContacts.cast<ProjectContact?>().firstWhere(
          (p) => p?.conversationKey == key,
          orElse: () => null,
        );
  }

  // ── Project session persistence helpers ─────────────────────

  void _saveProjectMessageToDb(LocalDb db, BridgeMessage msg) {
    final projectId = msg.projectId.isNotEmpty
        ? msg.projectId
        : _projectByConversationKey(_activeConversationKey)?.id ?? '';
    if (projectId.isEmpty) return;
    final sessionId = msg.sessionId.isNotEmpty
        ? msg.sessionId
        : (_activeProjectSessionId ?? '');
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

  Future<String?> _loadProjectSessionId(String projectId) async {
    if (_projectSessionIds.containsKey(projectId)) {
      return _projectSessionIds[projectId];
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('project_session_$projectId');
    if (saved != null && saved.isNotEmpty) {
      _projectSessionIds[projectId] = saved;
      return saved;
    }
    return null;
  }

  Future<void> _saveProjectSessionId(String projectId, String sessionId) async {
    _projectSessionIds[projectId] = sessionId;
    final prefs = await SharedPreferences.getInstance();
    if (sessionId.isEmpty) {
      await prefs.remove('project_session_$projectId');
    } else {
      await prefs.setString('project_session_$projectId', sessionId);
    }
  }
}
