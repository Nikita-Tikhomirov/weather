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
          SnackBar(content: Text(_projectDataLabels.projectChatsUnavailable)),
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

  void _applyStreamingProjectOutput(LocalDb db, BridgeMessage msg) {
    final handled = _mergeStreamingProjectOutput(msg);
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

  Widget _buildProjectChatView(TaskStore store, {required bool compact}) {
    final project = _projectByConversationKey(_activeConversationKey);
    if (project == null) {
      return Center(child: Text(_projectDataLabels.projectNotFound));
    }

    return ProjectChatView(
      project: project,
      bridge: _projectBridge,
      messages: _projectMessages,
      chatInputController: _chatInputCtl,
      // Keep bridge connection alive so session persists.
      // Messages are already saved to DB and will be restored on re-entry.
      onBack: _clearActiveConversation,
      onRequestBridgeStart: () => _requestProjectBridgeStart(project),
      onStartNewSession: _startNewProjectSession,
      onStopProjectPrompt: _stopProjectPrompt,
      onOpenBridgeSettings: _openBridgeSettings,
      onOpenProjectFiles: () => _openProjectFileManager(project),
      onReconnect: () {
        // Reconnect without clearing history.
        _projectBridge?.dispose();
        _projectBridge = null;
        _openProjectContact(store, project);
      },
      onSendPhotos: _sendProjectPhotos,
      onSendDocuments: _sendProjectDocuments,
      onSendMessage: _sendProjectMessage,
    );
  }

  void _sendProjectMessage() {
    final text = _chatInputCtl.text.trim();
    if (text.isEmpty) {
      return;
    }
    _chatInputCtl.clear();

    _projectBridge?.sendText(text);

    // Show the message immediately in the UI and persist to DB
    if (mounted) {
      final store = _store;
      final sentMsg = BridgeMessage(
        type: 'send',
        text: text,
        projectId: _projectByConversationKey(_activeConversationKey)?.id ?? '',
        sessionId: _activeProjectSessionId ?? '',
      );
      _addProjectMessage(sentMsg);
      if (store != null) {
        _saveProjectMessageToDb(store.repository.db, sentMsg);
      }
    }
  }

  void _openProjectFileManager(ProjectContact project) {
    // Request file tree, then show bottom sheet
    _setProjectFileBrowserLoading(
      path: '',
      statusMessage: BridgeMessage(
        type: 'status',
        text: _projectDataLabels.requestingProjectFiles,
      ),
    );
    _projectBridge?.requestFileTree();

    // Show bottom sheet immediately; it will update when files arrive
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _fileSheetSetState = setSheetState;
            return ProjectFileBrowser(
              project: project,
              files: _projectFiles,
              currentPath: _projectFileTreePath,
              isLoading: _projectFilesLoading,
              onNavigate: (path) {
                _setProjectFileBrowserLoading(path: path);
                setSheetState(() {});
                _projectBridge?.requestFileList(path);
              },
              onRefresh: () {
                _projectFiles = [];
                _projectFileTreePath = '';
                _projectFilesLoading = true;
                setSheetState(() {});
                _projectBridge?.requestFileTree();
              },
              onLinkToChat: (filePath) {
                final fullPath = '${project.path}/$filePath';
                final link = _projectDataLabels.fileLink(fullPath);
                final current = _chatInputCtl.text;
                _chatInputCtl.text = current.isEmpty ? link : '$current $link';
                // Close sheet so user can continue editing before sending
                Navigator.of(sheetContext).pop();
              },
              onViewFile: (filePath) {
                _projectBridge?.requestFileContent(filePath);
                // Show loading dialog over the file manager, update when content arrives
                _showFileContentOverlay(filePath);
              },
              onOpenFile: (filePath) {
                _projectBridge?.requestFileList(filePath);
                _setProjectFileBrowserLoading(path: filePath);
                setSheetState(() {});
              },
            );
          },
        );
      },
    ).then((_) {
      _fileSheetSetState = null;
    });
  }

  void _showFileContentOverlay(String path) {
    final ctl = ValueNotifier<String>(_projectDataLabels.fileContentLoading);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(path, style: const TextStyle(fontSize: 13)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ValueListenableBuilder<String>(
            valueListenable: ctl,
            builder: (_, text, __) => SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(_projectDataLabels.close),
          ),
        ],
      ),
    );
    // Store reference so bridge response can update it
    _pendingFileContent = ctl;
    _pendingFilePath = path;
  }

  /// Called when a file_content message arrives from the bridge
  void _onFileContentArrived(BridgeMessage msg) {
    if (_pendingFileContent == null) return;
    final path = msg.filePath.isNotEmpty ? msg.filePath : msg.projectId;
    if (path == _pendingFilePath || msg.fileContentText.isNotEmpty) {
      _pendingFileContent!.value = msg.fileContentText;
    }
  }

  void _showFileContentViewer(BridgeMessage msg) {
    final content = msg.text;
    final path = msg.filePath.isNotEmpty ? msg.filePath : msg.projectId;
    final hasError = content.isEmpty || content.startsWith('Error:');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            path.isNotEmpty
                                ? path.split('/').last
                                : _projectDataLabels.fileFallbackName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!hasError)
                          IconButton(
                            tooltip: _projectDataLabels.copyAll,
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: content));
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _projectDataLabels.copiedToClipboard,
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        IconButton(
                          tooltip: _projectDataLabels.close,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        path,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  const Divider(),
                  Expanded(
                    child: hasError
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                content.isEmpty
                                    ? _projectDataLabels.fileEmpty
                                    : content.replaceFirst('Error: ', ''),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              content,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _requestProjectBridgeStart(ProjectContact project) async {
    final ok = await ProjectBridgeService.requestBridgeStart(project);
    if (!mounted) {
      return;
    }
    _addProjectMessage(
      BridgeMessage(
        type: ok ? 'status' : 'error',
        text: ok
            ? _projectDataLabels.bridgeStartSent
            : _projectDataLabels.bridgeStartFailed,
      ),
    );
    if (ok) {
      final store = _store;
      if (store == null) {
        return;
      }
      _projectBridge?.dispose();
      _projectBridge = null;
      _openProjectContact(store, project);
    }
  }

  void _startNewProjectSession() {
    final store = _store;
    if (store == null) return;
    final project = _projectByConversationKey(_activeConversationKey);
    if (project == null) return;

    // Clear all persisted messages for this project
    store.repository.db.clearProjectMessages(project.id);
    _activeProjectSessionId = null;
    _projectSessionIds.remove(project.id);
    _saveProjectSessionId(project.id, '');

    _projectBridge?.startNewSession();
    if (!mounted) {
      return;
    }
    _resetProjectMessages(
      BridgeMessage(
        type: 'status',
        text: _projectDataLabels.newSessionStarting,
      ),
    );
  }

  void _stopProjectPrompt() {
    _projectBridge?.stopCurrentPrompt();
    if (!mounted) {
      return;
    }
    _addProjectMessage(
      BridgeMessage(
        type: 'status',
        text: _projectDataLabels.stopCommandSent,
      ),
    );
  }

  Future<void> _sendProjectPhotos() async {
    final bridge = _projectBridge;
    if (bridge == null) {
      return;
    }
    final picked = await _imagePicker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (picked.isEmpty) {
      return;
    }

    String caption = '';
    if (mounted) {
      final labels = _projectDataLabels;
      final captionCtl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(labels.photoCommentTitle),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: labels.deepSeekPromptHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(labels.saveOnly),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: Text(labels.send),
            ),
          ],
        ),
      );
      if (result != null) {
        caption = result;
      }
    }

    var sent = 0;
    var failed = 0;
    for (final file in picked) {
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e, st) {
        debugPrint('[bridge] file read error: $e\n$st');
        failed += 1;
        continue;
      }
      final ok = bridge.sendImage(
        fileName: file.name,
        mimeType: _projectImageMime(file),
        bytes: bytes,
        caption: caption,
      );
      if (ok) {
        sent += 1;
        if (mounted) {
          _addProjectMessage(
            BridgeMessage(
              type: 'sent_image',
              text: caption,
              imageBase64: base64Encode(bytes),
              imageMimeType: _projectImageMime(file),
              imageFilename: file.name,
            ),
          );
        }
      } else {
        failed += 1;
      }
    }
    if (!mounted) {
      return;
    }
    final statusMessages = <BridgeMessage>[];
    if (sent > 0) {
      statusMessages.add(
        BridgeMessage(
          type: 'send',
          text: _projectDataLabels.photosSavedToVision(sent),
        ),
      );
    }
    if (failed > 0 || sent == 0) {
      statusMessages.add(
        BridgeMessage(
          type: 'error',
          text: sent == 0
              ? _projectDataLabels.photosNotSent
              : _projectDataLabels.photosNotSentCount(failed),
        ),
      );
    }
    _addProjectMessages(statusMessages);
  }

  String _projectImageMime(XFile file) {
    final declared = file.mimeType?.trim();
    if (declared != null && declared.isNotEmpty) {
      return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) {
      return 'image/png';
    }
    if (name.endsWith('.webp')) {
      return 'image/webp';
    }
    if (name.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  Future<void> _sendProjectDocuments() async {
    final bridge = _projectBridge;
    if (bridge == null) {
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_attachmentLabels.fileReadFailed)),
          );
        }
        return;
      }

      final filePath = file.path!;
      final fileBytes = await File(filePath).readAsBytes();
      if (fileBytes.length > 15 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_attachmentLabels.fileTooLarge(maxMb: 15)),
            ),
          );
        }
        return;
      }

      // Prompt for caption
      String caption = '';
      if (mounted) {
        final labels = _projectDataLabels;
        final captionCtl = TextEditingController();
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(labels.documentCommentTitle),
            content: TextField(
              controller: captionCtl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: labels.deepSeekPromptHint,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: Text(labels.saveOnly),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
                child: Text(labels.send),
              ),
            ],
          ),
        );
        if (result != null) {
          caption = result;
        }
      }

      // Send to bridge
      bridge.sendUpload(
        fileBytes,
        file.name,
        guessMimeType(file.name),
        caption: caption,
      );

      if (mounted) {
        _addProjectMessage(
          BridgeMessage(
            type: 'send',
            text: _projectDataLabels.documentMessage(file.name),
            projectId:
                _projectByConversationKey(_activeConversationKey)?.id ?? '',
            sessionId: _activeProjectSessionId ?? '',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_attachmentLabels.documentSendFailed(error))),
        );
      }
    }
  }

  String guessMimeType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      case '7z':
        return 'application/x-7z-compressed';
      case 'mp3':
        return 'audio/mpeg';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _openBridgeSettings() async {
    final ctl = TextEditingController(
      text: await ProjectBridgeService.getServerAddress(),
    );
    if (!mounted) return;
    final labels = _projectDataLabels;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(labels.projectServerTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels.projectServerDescription,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                decoration: InputDecoration(
                  labelText: labels.addressLabel,
                  hintText: '192.168.1.5:9876',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await ProjectBridgeService.setServerAddress(ctl.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
                // Reconnect if we have a bridge
                if (_projectBridge != null) {
                  _projectBridge?.dispose();
                  _projectBridge = null;
                  // Re-trigger connection
                  final project =
                      _projectByConversationKey(_activeConversationKey);
                  if (project != null && mounted) {
                    _openProjectContact(_store!, project);
                  }
                }
              },
              child: Text(labels.save),
            ),
          ],
        );
      },
    );
  }
}
