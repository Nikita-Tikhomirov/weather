import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_labels.dart';
import '../../app/app_theme.dart';
import 'home_helpers.dart';
import '../../domain/task_domain_service.dart';
import '../chat/call_screen.dart';
import '../chat/chat_photo_viewer.dart';
import '../chat/messenger_page.dart';
import '../family/family_view.dart';
import '../projects/project_file_browser.dart';
import '../projects/project_chat_view.dart';
import '../profile/profile_page.dart';
import '../tasks/calendar_view.dart';
import '../tasks/dashboard_view.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/tasks_board.dart';
import '../../models/call_models.dart';
import '../../models/chat_models.dart';
import '../../models/project_contact.dart';
import '../../models/project_file.dart';
import '../../models/task_item.dart';
import '../../repositories/task_repository.dart';
import '../../services/api_client.dart';
import '../../services/call_service.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/desktop_process_host_service.dart';
import '../../services/desktop_theme_service.dart';
import '../../services/fcm_service.dart';
import '../../services/local_db.dart';
import '../../services/project_access.dart';
import '../../services/project_bridge_service.dart';
import '../../state/task_store.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.selectedThemeKey,
    required this.onThemeChanged,
  });

  final String selectedThemeKey;
  final ValueChanged<String> onThemeChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TaskStore? _store;
  FcmService? _fcm;
  DesktopThemeService? _desktopThemeService;
  DesktopProcessHostService? _desktopProcessHostService;
  Timer? _deltaSyncTimer;
  Timer? _fullSyncTimer;
  Timer? _retryTimer;
  Timer? _incomingCallPollTimer;
  bool _desktopLogExpanded = false;
  DateTime _desktopMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final ValueNotifier<String> _fcmDiagnostics =
      ValueNotifier('FCM: not initialized');
  final TextEditingController _chatInputCtl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  ChatRealtimeService? _chatRealtime;
  CallService? _callService;
  bool _chatLoading = false;
  String? _editingMessageId;
  List<ChatContact> _chatContacts = const <ChatContact>[];
  List<ChatContact> _phoneContacts = const <ChatContact>[];
  List<ChatContact> _familyMembers = const <ChatContact>[];
  List<ProjectContact> _projectContacts = const <ProjectContact>[];
  ProjectBridgeService? _projectBridge;
  final List<BridgeMessage> _projectMessages = <BridgeMessage>[];
  List<ProjectFileNode> _projectFiles = const <ProjectFileNode>[];
  String _projectFileTreePath = '';
  bool _projectFilesLoading = false;
  void Function(void Function())? _fileSheetSetState;
  ValueNotifier<String>? _pendingFileContent;
  String? _pendingFilePath;

  String? _activeProjectSessionId;
  final Map<String, String> _projectSessionIds = <String, String>{};
  List<ChatConversation> _chatConversations = const <ChatConversation>[];
  List<StickerPack> _chatStickerPacks = const <StickerPack>[];
  final Map<String, List<ChatMessage>> _chatMessagesByConversation =
      <String, List<ChatMessage>>{};
  String _activeConversationKey = '';
  String _currentProfileDisplayName = '';
  String _currentProfilePhone = '';
  String? _currentProfileAvatarUrl;
  final Map<String, String> _profileAvatarUrls = <String, String>{};
  ChatMessage? _replyToMessage;
  bool _isRecording = false;
  String? _voicePath;
  Timer? _voiceTimer;
  int _voiceSec = 0;
  Map<String, dynamic>? _pendingPushData;
  String _lastProcessedPushEventId = '';
  bool _pushAlreadyRouted = false;

  /// Conversation key -> set of profiles currently typing
  final Map<String, Set<String>> _typingUsers = <String, Set<String>>{};
  Timer? _typingSendTimer;

  bool get _isDesktopWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOwner = prefs.getString('actor_profile')?.trim() ?? '';
    _currentProfileDisplayName =
        prefs.getString('profile_display_name')?.trim() ?? '';
    _currentProfilePhone = prefs.getString('profile_phone')?.trim() ?? '';
    _currentProfileAvatarUrl = prefs
        .getString('avatar_${savedOwner.isNotEmpty ? savedOwner : 'default'}');
    final api = ApiClient(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://31.129.97.211',
      ),
      apiKey: const String.fromEnvironment(
        'API_KEY',
        defaultValue: 'dev-local-key',
      ),
    );
    String? owner;
    final savedPhone = prefs.getString('profile_phone')?.trim() ?? '';
    if (savedPhone.isNotEmpty) {
      try {
        owner = await _restoreProfileByPhone(api, prefs, savedPhone);
      } catch (_) {
        owner = savedOwner.isNotEmpty
            ? savedOwner
            : await _promptForInitialProfile(api);
      }
    } else if (savedOwner.isNotEmpty) {
      owner = savedOwner;
    } else {
      owner = await _promptForInitialProfile(api);
    }
    if (!mounted || owner == null || owner.isEmpty) {
      return;
    }

    // Load avatar for resolved owner
    final avatarKey = 'avatar_$owner';
    _currentProfileAvatarUrl = prefs.getString(avatarKey);
    if (mounted) setState(() {});

    final db = await LocalDb.open();
    final store = TaskStore(
      repository: TaskRepository(db: db, api: api),
      domainService: TaskDomainService(),
    );
    await store.initialize(initialOwner: owner);
    if (_isDesktopWindows) {
      await _initDesktopServices(store, owner);
    }
    _bindFcm(api: api, owner: owner);
    await _safeSyncFull(store, showErrors: false);
    _loadProjects();
    await _initChat(store);
    _initShareReceiver(store);
    _chatInputCtl.addListener(() => _onChatInputChanged(store));
    _startSyncLoops(store);
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() => _store = store);

    // Process push notification that arrived before initialization completed.
    var pending = _pendingPushData;

    // Also check temp file for payload saved by background handler.
    // This is a safety net in case FcmService.initialize() didn't process it.
    if (pending == null) {
      try {
        final file = File(
            '${Directory.systemTemp.path}/family_todo_pending_push.json');
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.isNotEmpty) {
            try {
              final decoded =
                  Map<String, dynamic>.from(jsonDecode(raw) as Map);
              pending = decoded;
              await file.delete();
              debugPrint(
                  '[FCM push] _init found pending in temp file');
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    if (pending != null) {
      final eventId = (pending['event_id'] ?? '').toString();
      if (eventId.isNotEmpty && _lastProcessedPushEventId == eventId) {
        debugPrint('[FCM push] _init skipping duplicate event $eventId');
        _pendingPushData = null;
        return;
      }
      _lastProcessedPushEventId = eventId;
      debugPrint(
          '[FCM push] _init processing pending: entity=${pending['entity']} conv=${pending['conversation_key']}');
      _pendingPushData = null;
      await _safeSyncDelta(store, showErrors: false);
      final pushType = (pending['type'] ?? pending['entity'] ?? '').toString();
      final conversationKey = (pending['conversation_key'] ?? '').trim();
      if (pushType == 'task_reminder' ||
          pushType == 'todo_update' ||
          (pending['entity'] ?? '') == 'task' ||
          (pending['entity'] ?? '') == 'family_task') {
        store.setPage(1);
      } else if ((pending['entity'] ?? '') == 'chat_message' &&
          conversationKey.isNotEmpty &&
          !isProjectConversation(conversationKey)) {
        _pushAlreadyRouted = true;
        store.setPage(4);
        // Wait for messenger tab to render before opening conversation
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          await _openConversation(store, conversationKey);
        }
      } else if (pushType == 'call_incoming') {
        final sessionId = (pending['session_id'] ?? '').toString();
        final callType = (pending['call_type'] ?? 'audio').toString();
        final callerProfile = (pending['caller_profile'] ?? '').toString();
        if (sessionId.isNotEmpty) {
          _callService?.notifyIncomingCall(CallSession(
            sessionId: sessionId,
            callerProfile: callerProfile,
            calleeProfile: store.owner.value,
            conversationKey: conversationKey,
            callType: callType,
            status: 'ringing',
            createdAt: DateTime.now().toIso8601String(),
          ));
        }
      } else {
        await _refreshActiveConversation(store, useNetwork: true, quiet: true);
      }
    }

  }

  Future<String> _ensureDeviceId(SharedPreferences prefs) async {
    final saved = prefs.getString('device_id')?.trim() ?? '';
    if (saved.isNotEmpty) {
      return saved;
    }
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    final value = 'dev-${DateTime.now().microsecondsSinceEpoch}-$random';
    await prefs.setString('device_id', value);
    return value;
  }

  Future<String> _restoreProfileByPhone(
    ApiClient api,
    SharedPreferences prefs,
    String phone,
  ) async {
    final deviceId = await _ensureDeviceId(prefs);
    final session = await api.deviceStart(
      phone: phone,
      deviceId: deviceId,
      displayName: _currentProfileDisplayName,
    );
    await prefs.setString('actor_profile', session.profileKey);
    await prefs.setString('profile_phone', session.phone);
    await prefs.setString('profile_display_name', session.displayName);
    _currentProfileDisplayName = session.displayName;
    _currentProfilePhone = session.phone;
    return session.profileKey;
  }

  Future<String?> _promptForInitialProfile(ApiClient api) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return null;
    }
    final phoneCtl = TextEditingController();
    final nameCtl = TextEditingController();
    String errorText = '';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Вход по номеру телефона'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      hintText: '+7 999 111 22 33',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Имя'),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(errorText, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    try {
                      final deviceId = await _ensureDeviceId(prefs);
                      final session = await api.deviceStart(
                        phone: phoneCtl.text,
                        deviceId: deviceId,
                        displayName: nameCtl.text,
                      );
                      await prefs.setString(
                        'actor_profile',
                        session.profileKey,
                      );
                      await prefs.setString('profile_phone', session.phone);
                      await prefs.setString(
                        'profile_display_name',
                        session.displayName,
                      );
                      if (mounted) {
                        setState(() {
                          _currentProfileDisplayName = session.displayName;
                          _currentProfilePhone = session.phone;
                        });
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(session.profileKey);
                      }
                    } catch (error) {
                      setDialogState(() => errorText = error.toString());
                    }
                  },
                  child: const Text('Продолжить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initDesktopServices(TaskStore store, String owner) async {
    final themeService = DesktopThemeService();
    await themeService.initialize(initialProfile: owner);
    store.setDesktopTheme(
      mode: themeService.state.value.mode,
      scheme: themeService.state.value.scheme,
      schemes: themeService.state.value.availableSchemes,
      tokens: themeService.state.value.tokens,
    );
    themeService.state.addListener(() {
      final state = themeService.state.value;
      store.setDesktopTheme(
        mode: state.mode,
        scheme: state.scheme,
        schemes: state.availableSchemes,
        tokens: state.tokens,
      );
    });
    _desktopThemeService = themeService;

    _desktopProcessHostService = DesktopProcessHostService(
      workingDirectory: Directory.current.path,
      onVoiceState: store.setVoiceHostState,
      onLog: (message, {isError = false}) {
        final stamp = DateTime.now().toIso8601String().substring(11, 19);
        final level = isError ? 'ERR' : 'INFO';
        store.appendDesktopLog('[$stamp][$level] $message');
      },
    );
  }

  Widget _buildDesktopShell({
    required TaskStore store,
    required bool loading,
    required String owner,
    required DateTime selectedDate,
    required String selectedDateKey,
  }) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: store.desktopThemeTokens,
      builder: (context, tokens, _) {
        final bgApp = colorFromToken(tokens, 'bg_app', const Color(0xFFF1F5F9));
        final bgPanel =
            colorFromToken(tokens, 'bg_panel', const Color(0xFFFFFFFF));
        final textPrimary =
            colorFromToken(tokens, 'text_primary', const Color(0xFF0F172A));
        final border =
            colorFromToken(tokens, 'border', const Color(0xFFE2E8F0));
        return Scaffold(
          body: Container(
            color: bgApp,
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bgPanel,
                      border: Border(
                        bottom: BorderSide(color: border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Семейные задачи - $selectedDateKey',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<int>(
                          valueListenable: store.pageIndex,
                          builder: (context, page, __) {
                            return SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 0, label: Text('Сводка')),
                                ButtonSegment(value: 1, label: Text('Задачи')),
                                ButtonSegment(
                                    value: 2, label: Text('Календарь')),
                                ButtonSegment(value: 3, label: Text('Семья')),
                                ButtonSegment(
                                    value: 4, label: Text('Мессенджер')),
                              ],
                              selected: {page},
                              onSelectionChanged: (value) =>
                                  store.setPage(value.first),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: store.themeMode,
                          builder: (context, mode, __) {
                            return SegmentedButton<String>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                    value: 'light', label: Text('Свет')),
                                ButtonSegment(
                                    value: 'dark', label: Text('Тьма')),
                              ],
                              selected: {mode},
                              onSelectionChanged: (value) =>
                                  _setDesktopThemeMode(value.first),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<List<String>>(
                          valueListenable: store.availableSchemes,
                          builder: (context, schemes, __) {
                            return ValueListenableBuilder<String>(
                              valueListenable: store.themeScheme,
                              builder: (context, scheme, ___) {
                                final safeScheme = schemes.contains(scheme) &&
                                        schemes.isNotEmpty
                                    ? scheme
                                    : (schemes.isEmpty ? '' : schemes.first);
                                return DropdownButton<String>(
                                  value: safeScheme.isEmpty ? null : safeScheme,
                                  hint: const Text('Тема'),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _setDesktopThemeScheme(value);
                                    }
                                  },
                                  items: schemes
                                      .map(
                                        (item) => DropdownMenuItem<String>(
                                          value: item,
                                          child: Text(item),
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<DesktopHostState>(
                          valueListenable: store.voiceHostState,
                          builder: (context, voiceState, __) {
                            final enabled =
                                voiceState.status == DesktopHostStatus.running;
                            return Row(
                              children: [
                                const Text('Голос'),
                                Switch(
                                  value: enabled,
                                  onChanged: (value) =>
                                      _toggleVoiceHost(store, value),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        ValueListenableBuilder<int>(
                          valueListenable: store.pageIndex,
                          builder: (context, page, __) {
                            return FilledButton.icon(
                              onPressed: () => _openTaskEditor(
                                store,
                                forceFamily: page == 3,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить'),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Синхронизация',
                          icon: const Icon(Icons.sync),
                          onPressed: () =>
                              _safeSyncFull(store, showErrors: true),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: store.canUndo,
                          builder: (context, canUndo, __) {
                            return IconButton(
                              tooltip: 'Отменить',
                              onPressed: canUndo
                                  ? () async {
                                      final ok = await store.undoLastAction();
                                      if (ok) {
                                        await _safeSyncDelta(
                                          store,
                                          showErrors: false,
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.undo),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildDesktopPageContent(store, selectedDate),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    height: _desktopLogExpanded ? 150 : 44,
                    decoration: BoxDecoration(
                      color: bgPanel,
                      border: Border(top: BorderSide(color: border)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => setState(
                            () => _desktopLogExpanded = !_desktopLogExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _desktopLogExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_up,
                                ),
                                const SizedBox(width: 8),
                                const Text('Desktop logs'),
                              ],
                            ),
                          ),
                        ),
                        if (_desktopLogExpanded)
                          Expanded(
                            child: ValueListenableBuilder<List<String>>(
                              valueListenable: store.desktopLogEntries,
                              builder: (context, logs, __) {
                                return ListView.builder(
                                  reverse: true,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    return Text(logs[logs.length - 1 - index]);
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopPageContent(TaskStore store, DateTime selectedDate) {
    return ValueListenableBuilder<int>(
      valueListenable: store.pageIndex,
      builder: (context, page, _) {
        if (page == 0) {
          return ValueListenableBuilder<DashboardVm>(
            valueListenable: store.dashboard,
            builder: (context, vm, __) {
              return DashboardView(
                vm: vm,
                labelFor: _profileLabel,
                onOpenCalendar: () async {
                  store.setPage(2);
                },
              );
            },
          );
        }
        if (page == 1) {
          return ValueListenableBuilder<Map<String, List<TaskItem>>>(
            valueListenable: store.personalByStatus,
            builder: (context, byStatus, __) {
              final selectedDateKey = dateKey(selectedDate);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            store.setSelectedDate(picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_month),
                        label: Text('Дата: $selectedDateKey'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: DesktopTasksBoard(
                      byStatus: byStatus,
                      labelFor: _profileLabel,
                      selectionMode: false,
                      selectedIds: const <String>{},
                      onToggleSelect: (_) {},
                      onDropStatus: (item, status) async {
                        await store.move(item, status);
                        await _safeSyncDelta(
                          store,
                          showErrors: true,
                        );
                      },
                      onEdit: (task) => _openTaskEditor(store, existing: task),
                      onDelete: (task) async {
                        await store.delete(task);
                        await _safeSyncDelta(
                          store,
                          showErrors: true,
                        );
                      },
                      onDoneToggle: (task) async {
                        await store.toggleDone(task);
                        await _safeSyncDelta(
                          store,
                          showErrors: true,
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        }
        if (page == 2) {
          return ValueListenableBuilder<List<TaskItem>>(
            valueListenable: store.allTasksView,
            builder: (context, tasks, __) {
              return DesktopCalendarView(
                month: _desktopMonth,
                selectedDate: selectedDate,
                allTasks: tasks,
                monthGrid: _monthGrid(_desktopMonth),
                onGoPrevMonth: () => setState(
                  () => _desktopMonth = DateTime(
                    _desktopMonth.year,
                    _desktopMonth.month - 1,
                  ),
                ),
                onGoNextMonth: () => setState(
                  () => _desktopMonth = DateTime(
                    _desktopMonth.year,
                    _desktopMonth.month + 1,
                  ),
                ),
                onGoToday: () => setState(() {
                  final now = DateTime.now();
                  _desktopMonth = DateTime(now.year, now.month);
                  store.setSelectedDate(now);
                }),
                onSelectDate: (date) => store.setSelectedDate(date),
                onDropToDay: (task, targetDay) =>
                    _moveToDate(store, task, targetDay),
                onDropToStatus: (task, status) async {
                  await store.move(task, status);
                  await _safeSyncDelta(store, showErrors: true);
                },
                onOpenEditor: (day, task) async {
                  store.setSelectedDate(day);
                  await _openTaskEditor(store, existing: task);
                },
                onDelete: (task) async {
                  await store.delete(task);
                  await _safeSyncDelta(store, showErrors: true);
                },
                onAddForDate: (day) async {
                  store.setSelectedDate(day);
                  await _openTaskEditor(store);
                },
              );
            },
          );
        }
        if (page == 3) {
          return ValueListenableBuilder<String>(
            valueListenable: store.familyFilter,
            builder: (context, familyFilter, _) {
              return ValueListenableBuilder<List<TaskItem>>(
                valueListenable: store.familyTasksView,
                builder: (context, tasks, __) {
                  return FamilyView(
                    familyTasks: tasks,
                    familyFilter: familyFilter,
                    labelFor: _profileLabel,
                    onFilterChanged: store.setFamilyFilter,
                    onEdit: (task) => _openTaskEditor(store, existing: task),
                    onDelete: (task) async {
                      await store.delete(task);
                      await _safeSyncDelta(store, showErrors: true);
                    },
                  );
                },
              );
            },
          );
        }
        return _buildMessengerPage(store, compact: false);
      },
    );
  }

  void _bindFcm({required ApiClient api, required String owner}) {
    _fcm?.dispose();
    if (mounted) {
      _fcmDiagnostics.value = 'FCM: binding actor=$owner';
    }
    _fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (_) {
        // No snackbar — only system notification is shown
      },
      onDiagnosticsChanged: (text) {
        debugPrint('FCM diagnostics: $text');
        if (!mounted) {
          return;
        }
        _fcmDiagnostics.value = text;
      },
      onOpenPush: (data) async {
        final store = _store;
        debugPrint(
            '[FCM push] onOpenPush: entity=${data['entity']} conv=${data['conversation_key']} store=${store != null}');
        if (store == null) {
          // Store for later processing once initialization completes
          debugPrint('[FCM push] store is null, saving to _pendingPushData');
          _pendingPushData = Map<String, dynamic>.from(data);
          return;
        }
        final eventId = (data['event_id'] ?? '').toString();
        if (eventId.isNotEmpty && _lastProcessedPushEventId == eventId) {
          debugPrint('[FCM push] skipping duplicate event $eventId');
          return;
        }
        _lastProcessedPushEventId = eventId;
        await _safeSyncDelta(store, showErrors: false);

        final pushType = (data['type'] ?? data['entity'] ?? '').toString();
        final conversationKey = (data['conversation_key'] ?? '').trim();

        // Task-related notifications -> go to tasks tab
        if (pushType == 'task_reminder' ||
            pushType == 'todo_update' ||
            (data['entity'] ?? '') == 'task' ||
            (data['entity'] ?? '') == 'family_task') {
          debugPrint('[FCM push] routing to tasks tab');
          store.setPage(1); // Switch to Tasks tab
          return;
        }

        // Chat messages -> go to messenger
        if ((data['entity'] ?? '') == 'chat_message' &&
            conversationKey.isNotEmpty &&
            !isProjectConversation(conversationKey)) {
          debugPrint(
              '[FCM push] routing to messenger -> _openConversation($conversationKey)');
          _pushAlreadyRouted = true;
          store.setPage(4); // Switch to Messenger tab
          // Wait for messenger tab to render before opening conversation
          await WidgetsBinding.instance.endOfFrame;
          if (mounted) {
            await _openConversation(store, conversationKey);
          }
          return;
        }

        // Incoming call -> show call screen
        if (pushType == 'call_incoming') {
          final sessionId = (data['session_id'] ?? '').toString();
          final callType = (data['call_type'] ?? 'audio').toString();
          final callerProfile = (data['caller_profile'] ?? '').toString();
          if (sessionId.isNotEmpty && mounted) {
            final session = CallSession(
              sessionId: sessionId,
              callerProfile: callerProfile,
              calleeProfile: (store.owner.value),
              conversationKey: conversationKey,
              callType: callType,
              status: 'ringing',
              createdAt: DateTime.now().toIso8601String(),
            );
            _callService?.notifyIncomingCall(session);
          }
          return;
        }

        // Call ended remotely
        if (pushType == 'call_accepted' || pushType == 'call_rejected') {
          return;
        }

        // Default: just refresh
        await _refreshActiveConversation(store, useNetwork: true, quiet: true);
      },
    );
    _fcm!.initialize().catchError((error, stackTrace) {
      debugPrint('FCM initialization failed: $error');
      debugPrint('$stackTrace');
    });
  }

  void _showFcmDiagnosticsDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<String>(
          valueListenable: _fcmDiagnostics,
          builder: (context, text, _) {
            return AlertDialog(
              title: const Text('FCM диагностика'),
              content: SingleChildScrollView(
                child: SelectableText(text),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    _fcmDiagnostics.value = 'FCM: обновляю диагностику...';
                    await _fcm?.refreshDiagnostics();
                  },
                  child: const Text('Обновить'),
                ),
                TextButton(
                  onPressed: () async {
                    _fcmDiagnostics.value = 'FCM: сбрасываю токен...';
                    await _fcm?.refreshDiagnostics(forceResetToken: true);
                  },
                  child: const Text('Сбросить токен'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Закрыть'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _startSyncLoops(TaskStore store) {
    _cancelSyncLoops();
    _deltaSyncTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      await _safeSyncDelta(store, showErrors: false);
    });
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      await _safeSyncFull(store, showErrors: false);
    });
    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      _retryPendingMessages(store);
    });
    _incomingCallPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollIncomingCall(store);
    });
    // Also try immediately on startup
    _retryPendingMessages(store);
    _pollIncomingCall(store);
  }

  void _cancelSyncLoops() {
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _fullSyncTimer?.cancel();
    _fullSyncTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _incomingCallPollTimer?.cancel();
    _incomingCallPollTimer = null;
  }

  void _replaceCallService({
    required ApiClient api,
    required String actorProfile,
  }) {
    _callService?.dispose();
    _callService = CallService(api: api, actorProfile: actorProfile)
      ..onIncomingCall = _handleIncomingCall
      ..onCallEnded = () {
        if (mounted) setState(() {});
      };
  }

  Future<void> _pollIncomingCall(TaskStore store) async {
    final service = _callService;
    if (!mounted ||
        service == null ||
        (service.state != CallState.idle && service.state != CallState.ended)) {
      return;
    }

    try {
      final session = await store.repository.api.callCheckIncoming(
        actorProfile: store.owner.value,
      );
      if (session != null && mounted) {
        service.notifyIncomingCall(session);
      }
    } catch (_) {
      // FCM is primary; polling is a quiet fallback for missed call pushes.
    }
  }

  Future<void> _safeSyncDelta(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncDelta();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }

  Future<void> _safeSyncFull(
    TaskStore store, {
    required bool showErrors,
  }) async {
    try {
      await store.syncFull();
    } catch (error) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка синхронизации: $error')));
      }
    }
  }

  void _initShareReceiver(TaskStore store) {
    const channel = MethodChannel('family_todo_mobile/share');
    channel.setMethodCallHandler((call) async {
      if (call.method != 'onShareReceived') return;
      final args = call.arguments as Map<dynamic, dynamic>?;
      if (args == null || !mounted) return;
      final text = (args['text'] as String?)?.trim() ?? '';
      final imageUris =
          (args['imageUris'] as List?)?.map((e) => e.toString()).toList() ??
              const [];
      final videoUris =
          (args['videoUris'] as List?)?.map((e) => e.toString()).toList() ??
              const [];

      // Wait a moment for UI to settle
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      // Show contact picker to forward shared content
      final allContacts = _allKnownContacts(store)
          .where((c) => c.profileKey != store.owner.value)
          .toList();
      if (allContacts.isEmpty) return;

      final selected = await showDialog<ChatContact>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:
              Text(text.isNotEmpty ? 'Поделиться текстом' : 'Поделиться фото'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: allContacts.length,
              itemBuilder: (_, i) => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(contactLabel(allContacts[i])),
                onTap: () => Navigator.pop(ctx, allContacts[i]),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;

      var conversationKey = selected.conversationKey;
      if (conversationKey.isEmpty) {
        final members = [store.owner.value, selected.profileKey]..sort();
        conversationKey = 'dm:${members[0]}:${members[1]}';
      }

      final api = store.repository.api;
      try {
        if (text.isNotEmpty) {
          await api.chatSendMessage(
            actorProfile: store.owner.value,
            conversationKey: conversationKey,
            messageType: 'text',
            text: text,
          );
        }
        if (imageUris.isNotEmpty) {
          final attachments = <ChatAttachment>[];
          for (var i = 0; i < imageUris.length; i++) {
            final uri = imageUris[i];
            try {
              final file = File(uri);
              final bytes = await file.readAsBytes();
              final uploaded = await api.chatUploadSticker(
                actorProfile: store.owner.value,
                bytes: bytes,
                filename: 'shared_image.jpg',
              );
              attachments.add(ChatAttachment(
                kind: 'image',
                assetUrl: uploaded.assetUrl,
                imageMeta: uploaded.imageMeta,
                sortOrder: attachments.length,
              ));
            } catch (_) {
              // skip images that fail to read or upload
            }
          }
          if (attachments.isNotEmpty) {
            await api.chatSendMessage(
              actorProfile: store.owner.value,
              conversationKey: conversationKey,
              messageType: attachments.length == 1 ? 'image' : 'image_group',
              attachments: attachments,
            );
          }
        }
        if (videoUris.isNotEmpty) {
          final attachments = <ChatAttachment>[];
          for (var i = 0; i < videoUris.length; i++) {
            final uri = videoUris[i];
            try {
              final file = File(uri);
              final bytes = await file.readAsBytes();
              final uploaded = await api.chatUploadSticker(
                actorProfile: store.owner.value,
                bytes: bytes,
                filename: 'shared_video.mp4',
              );
              attachments.add(ChatAttachment(
                kind: 'video',
                assetUrl: uploaded.assetUrl,
                imageMeta: uploaded.imageMeta,
                sortOrder: attachments.length,
              ));
            } catch (_) {
              // skip videos that fail to read or upload
            }
          }
          if (attachments.isNotEmpty) {
            await api.chatSendMessage(
              actorProfile: store.owner.value,
              conversationKey: conversationKey,
              messageType: attachments.length == 1 ? 'video' : 'video_group',
              attachments: attachments,
            );
          }
        }
        setState(() => _activeConversationKey = conversationKey);
        // Mark messages as read
        store.repository.api
            .chatMarkRead(
              actorProfile: store.owner.value,
              conversationKey: conversationKey,
            )
            .catchError((_) {});
        await _refreshConversation(store, conversationKey,
            useNetwork: true, quiet: true);
      } catch (_) {
        // silently ignore share errors
      }
    });
    // Signal to Android that Flutter is ready to receive share data
    channel.invokeMethod('ready');
  }

  Future<void> _refreshChatBootstrap(TaskStore store) async {
    try {
      final bootstrap = await store.repository.api.chatBootstrap(
        actorProfile: store.owner.value,
      );
      await store.repository.db.replaceConversations(bootstrap.conversations);
      await store.repository.db.replaceStickerPacks(bootstrap.stickerPacks);
      final contacts = bootstrap.contacts;
      if (mounted) {
        await _saveAvatarUrlsFromContacts(contacts);
        await _loadProfileAvatars([
          ...contacts.map((item) => item.profileKey),
          ...bootstrap.conversations.expand((item) => item.members),
        ]);
        setState(() {
          _chatContacts = contacts;
          _chatConversations = bootstrap.conversations;
          _chatStickerPacks = bootstrap.stickerPacks;
        });
      }
    } catch (_) {
      // Silently fail — user will see stale data
    }
  }

  Future<void> _refreshMessengerContacts(TaskStore store) async {
    await _refreshChatBootstrap(store);
    await _loadPhoneContacts(store);
  }

  Future<void> _removeLocalConversation(
    TaskStore store,
    String conversationKey,
  ) async {
    final key = conversationKey.trim();
    if (key.isEmpty) {
      return;
    }
    await store.repository.db.deleteConversation(key);
    if (!mounted) {
      return;
    }
    setState(() {
      _chatConversations.removeWhere((item) => item.conversationKey == key);
      _chatMessagesByConversation.remove(key);
      if (_activeConversationKey == key) {
        _activeConversationKey = '';
      }
    });
  }

  Future<void> _initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    // If a push already routed to a conversation, preserve the key
    // so _initChat doesn't undo the navigation.
    final pushConversationKey =
        _pushAlreadyRouted ? _activeConversationKey : '';

    setState(() {
      _chatLoading = true;
      _chatMessagesByConversation.clear();
      if (!_pushAlreadyRouted) {
        _activeConversationKey = '';
      }
    });

    try {
      final bootstrap = await api.chatBootstrap(actorProfile: actor);
      await db.replaceConversations(bootstrap.conversations);
      await db.replaceStickerPacks(bootstrap.stickerPacks);

      final conversations = await db.readConversations();
      final stickerPacks = await db.readStickerPacks();

      if (!mounted) {
        return;
      }
      await _saveAvatarUrlsFromContacts(bootstrap.contacts);
      await _loadProfileAvatars([
        ...bootstrap.contacts.map((item) => item.profileKey),
        ...conversations.expand((item) => item.members),
      ]);
      setState(() {
        _chatContacts = bootstrap.contacts;
        _chatConversations = conversations;
        _chatStickerPacks = stickerPacks;
        if (!_pushAlreadyRouted) {
          _activeConversationKey = '';
        }
      });

      await _loadPhoneContacts(store);
      await _chatRealtime?.stop();
      _chatRealtime = ChatRealtimeService(
        api: api,
        actorProfile: actor,
        activeConversationKey: () => _activeConversationKey,
        shouldPoll: () =>
            mounted &&
            _store?.pageIndex.value == 4 &&
            !isProjectConversation(_activeConversationKey),
        onMessagesUpdated: (conversationKey) async {
          await _refreshConversation(
            store,
            conversationKey,
            useNetwork: true,
            quiet: true,
          );
        },
      )..start();

      _replaceCallService(api: api, actorProfile: actor);

      // If a push already opened a conversation, refresh it now that
      // chat state is fully loaded.
      if (pushConversationKey.isNotEmpty && mounted) {
        await _refreshConversation(
          store,
          pushConversationKey,
          useNetwork: true,
          quiet: true,
        );
      }

      // Load avatars for all contacts from local storage
      final prefs = await SharedPreferences.getInstance();
      for (final contact in [..._chatContacts, ..._familyMembers]) {
        if (_profileAvatarUrls.containsKey(contact.profileKey)) continue;
        final avatar = prefs.getString('avatar_${contact.profileKey}');
        if (avatar != null && avatar.isNotEmpty) {
          _profileAvatarUrls[contact.profileKey] = avatar;
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Чат недоступен: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _chatLoading = false;
        });
      }
    }
  }

  void _loadProjects() {
    if (!canUseProjectChats(_currentProfilePhone)) {
      if (mounted) {
        setState(() => _projectContacts = const <ProjectContact>[]);
      }
      return;
    }
    try {
      // Try multiple locations for projects.json
      final candidates = <String>[
        'family_data/nik/projects.json',
        '${Directory.current.path}/family_data/nik/projects.json',
      ];
      // Remove duplicate slashes
      final normalized = candidates
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
        // Fallback: use bundled project list so contacts appear on all platforms
        if (mounted) {
          setState(() {
            _projectContacts = _fallbackProjects();
          });
        }
        return;
      }

      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final rawList = json['projects'] as List<dynamic>? ?? [];
      final projects = rawList
          .whereType<Map<String, dynamic>>()
          .map((item) => ProjectContact.fromJson(item))
          .toList();
      if (mounted) {
        setState(() => _projectContacts = projects);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _projectContacts = _fallbackProjects());
      }
    }
  }

  List<ProjectContact> _fallbackProjects() {
    // Built-in list synced with family_data/nik/projects.json
    return const [
      ProjectContact(
          id: 'tudushka',
          name: 'Тудушка',
          path: r'C:\Users\user\Desktop\weather',
          icon: 'terminal'),
      ProjectContact(
          id: 'cifra',
          name: 'Цифра',
          path: r'C:\Users\user\Desktop\depseeker_test',
          icon: 'code'),
      ProjectContact(
          id: 'stylish-house',
          name: 'Stylysh-house',
          path: r'C:\Users\user\Desktop\stylish-house',
          icon: 'code'),
      ProjectContact(
          id: 'exp76',
          name: 'Exp76',
          path: r'C:\Users\user\Desktop\exp76.ru',
          icon: 'code'),
      ProjectContact(
          id: 'groot',
          name: 'Грут',
          path: r'C:\Users\user\Desktop\Грут',
          icon: 'code'),
      ProjectContact(
          id: 'nousro',
          name: 'Nousro',
          path: r'C:\Users\user\Desktop\nousro',
          icon: 'folder'),
    ];
  }

  Future<void> _openProjectContact(
      TaskStore store, ProjectContact project) async {
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
    setState(() {
      _activeConversationKey = project.conversationKey;
    });

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

    setState(() {
      _projectMessages
        ..clear()
        ..addAll(restoredMessages);
    });

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
              setState(() => _projectMessages.addAll(newMsgs));
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
            setState(() {
              _projectContacts =
                  msg.projects.map((p) => ProjectContact.fromJson(p)).toList();
            });
          }
          if (msg.isFiles) {
            setState(() {
              _projectFiles = msg.files;
              _projectFilesLoading = false;
            });
            _fileSheetSetState?.call(() {});
          }
          if (msg.isFileContent) {
            setState(() => _projectMessages.add(msg));
            _onFileContentArrived(msg);
            if (mounted) {
              _showFileContentViewer(msg);
            }
            return;
          }
          setState(() => _projectMessages.add(msg));
        }
      },
      onStatusChange: (connected, status) {
        if (mounted) {
          setState(() {
            _projectMessages.add(BridgeMessage(
              type: 'status',
              text: status,
            ));
          });
        }
      },
    );

    setState(() => _projectBridge = bridge);

    bridge.startProject(project, resumeSessionId: savedSessionId);
    final ok = await bridge.connect();
    if (!ok) return;
  }

  void _applyStreamingProjectOutput(LocalDb db, BridgeMessage msg) {
    var handled = false;
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

  // ── Existing methods ─────────────────────────────────────────

  Future<void> _refreshActiveConversation(
    TaskStore store, {
    required bool useNetwork,
    required bool quiet,
  }) async {
    if (_activeConversationKey.isEmpty) {
      return;
    }
    // Skip project conversations (handled by bridge)
    if (isProjectConversation(_activeConversationKey)) {
      return;
    }
    await _refreshConversation(
      store,
      _activeConversationKey,
      useNetwork: useNetwork,
      quiet: quiet,
    );
  }

  Future<void> _refreshConversation(
    TaskStore store,
    String conversationKey, {
    required bool useNetwork,
    required bool quiet,
  }) async {
    conversationKey = canonicalConversationKey(conversationKey);
    final db = store.repository.db;
    final api = store.repository.api;
    final actor = store.owner.value;
    final previous =
        _chatMessagesByConversation[conversationKey] ?? const <ChatMessage>[];

    try {
      final local = _mergeTransientMessages(
        await db.readMessages(conversationKey: conversationKey),
        previous,
      );
      if (mounted && !sameMessages(previous, local)) {
        setState(() {
          _chatMessagesByConversation[conversationKey] = local;
        });
      }

      if (!useNetwork) {
        return;
      }

      final snapshot = await api.chatFetchMessages(
        actorProfile: actor,
        conversationKey: conversationKey,
        limit: 100,
      );
      final canonicalKey = snapshot.messages.isEmpty
          ? conversationKey
          : canonicalConversationKey(snapshot.messages.first.conversationKey);
      await db.upsertMessages(snapshot.messages);
      if (snapshot.nextCursor != null && snapshot.nextCursor!.isNotEmpty) {
        await db.saveChatCursor(
          conversationKey: canonicalKey,
          cursor: snapshot.nextCursor!,
        );
      }

      final merged = _mergeTransientMessages(
        await db.readMessages(conversationKey: canonicalKey),
        _chatMessagesByConversation[canonicalKey] ?? previous,
      );
      final beforeMerged =
          _chatMessagesByConversation[canonicalKey] ?? const <ChatMessage>[];
      final messagesChanged = !sameMessages(beforeMerged, merged);
      final nextTyping = _typingProfilesFor(snapshot.typingProfiles, actor);
      final typingChanged = !setEquals(
          _typingUsers[canonicalKey] ?? const <String>{}, nextTyping);
      final conversationKeyChanged =
          _activeConversationKey == conversationKey &&
              canonicalKey != conversationKey;
      if (mounted &&
          (messagesChanged || typingChanged || conversationKeyChanged)) {
        setState(() {
          if (messagesChanged) {
            _chatMessagesByConversation[canonicalKey] = merged;
          }
          if (typingChanged) {
            _setTypingUsers(canonicalKey, nextTyping);
          }
          if (conversationKeyChanged) {
            _activeConversationKey = canonicalKey;
          }
        });
      }
      _markDelivered(canonicalKey, snapshot.messages);
    } catch (error) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления чата: $error')),
        );
      }
    }
  }

  List<ChatMessage> _mergeTransientMessages(
    List<ChatMessage> serverMessages,
    List<ChatMessage> currentMessages,
  ) {
    final merged = List<ChatMessage>.from(serverMessages);
    for (final message in currentMessages) {
      final isTransient = message.isUploading ||
          message.deliveryStatus == 'sending' ||
          message.deliveryStatus == 'failed';
      if (!isTransient) continue;
      final alreadyResolved = merged.any((item) =>
          item.id == message.id ||
          (message.clientMessageId != null &&
              message.clientMessageId!.isNotEmpty &&
              item.clientMessageId == message.clientMessageId));
      if (!alreadyResolved) {
        merged.add(message);
      }
    }
    return merged;
  }

  Set<String> _typingProfilesFor(List<String> profiles, String owner) {
    return profiles
        .where((profile) => profile.isNotEmpty && profile != owner)
        .toSet();
  }

  void _setTypingUsers(String conversationKey, Set<String> profiles) {
    if (profiles.isEmpty) {
      _typingUsers.remove(conversationKey);
    } else {
      _typingUsers[conversationKey] = profiles;
    }
  }

  Future<void> _openConversation(
      TaskStore store, String conversationKey) async {
    if (!mounted) {
      return;
    }
    conversationKey = canonicalConversationKey(conversationKey);
    // Clean up project bridge when switching to regular conversation
    if (isProjectConversation(_activeConversationKey)) {
      _projectBridge?.dispose();
      _projectBridge = null;
      _projectMessages.clear();
    }
    // Ensure the conversation exists in the list (optimistic entry for push opens)
    final existing =
        _chatConversations.any((c) => c.conversationKey == conversationKey);
    if (!existing && !isProjectConversation(conversationKey)) {
      _chatConversations = [
        ..._chatConversations,
        ChatConversation(
          conversationKey: conversationKey,
          kind: 'direct',
          title: '',
          members: conversationKey.startsWith('dm:')
              ? conversationKey.split(':').skip(1).toList()
              : [store.owner.value],
        ),
      ];
    }
    setState(() {
      _activeConversationKey = conversationKey;
    });
    await _refreshConversation(
      store,
      conversationKey,
      useNetwork: true,
      quiet: true,
    );
    await _chatRealtime?.tick();
  }

  String canonicalConversationKey(String key) {
    final trimmed = key.trim();
    final parts = trimmed.split(':');
    if (parts.length == 3 && parts[0] == 'dm') {
      final members = [parts[1], parts[2]]..sort();
      return 'dm:${members[0]}:${members[1]}';
    }
    return trimmed;
  }

  Future<void> _openDirectContact(TaskStore store, ChatContact contact) async {
    final key = _directConversationKeyFor(store.owner.value, contact);
    final existing =
        _chatConversations.any((item) => item.conversationKey == key);
    if (!existing) {
      setState(() {
        _chatConversations = [
          ..._chatConversations,
          ChatConversation(
            conversationKey: key,
            kind: 'direct',
            title: '',
            members: [store.owner.value, contact.profileKey],
          ),
        ];
      });
    }
    await _openConversation(store, key);
  }

  String _directConversationKeyFor(String actor, ChatContact contact) {
    final existing = _chatConversations.cast<ChatConversation?>().firstWhere(
          (item) =>
              item != null &&
              item.kind == 'direct' &&
              item.members.contains(actor) &&
              item.members.contains(contact.profileKey),
          orElse: () => null,
        );
    if (existing != null) {
      return existing.conversationKey;
    }

    final remoteKey = contact.conversationKey.trim();
    if (remoteKey.startsWith('dm:')) {
      return remoteKey;
    }

    final members = [actor, contact.profileKey]..sort();
    return 'dm:${members[0]}:${members[1]}';
  }

  Future<void> _openCreateGroupSheet(TaskStore store) async {
    final selected = <String>{};
    final titleCtl = TextEditingController(text: 'Новая группа');
    final contacts = _phoneContacts.isEmpty ? _chatContacts : _phoneContacts;
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtl,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final contact in contacts)
                          CheckboxListTile(
                            value: selected.contains(contact.profileKey),
                            title: Text(contactLabel(contact)),
                            subtitle: Text(contact.phone),
                            onChanged: (value) {
                              setSheetState(() {
                                if (value == true) {
                                  selected.add(contact.profileKey);
                                } else {
                                  selected.remove(contact.profileKey);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(sheetContext).pop(true),
                    icon: const Icon(Icons.check),
                    label: const Text('Создать'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (created != true || selected.isEmpty) {
      return;
    }
    final conversation = await store.repository.api.chatCreateGroup(
      actorProfile: store.owner.value,
      title: titleCtl.text,
      memberProfiles: selected.toList(),
    );
    await store.repository.db.upsertConversation(conversation);
    setState(() {
      _chatConversations = [..._chatConversations, conversation];
      _activeConversationKey = conversation.conversationKey;
    });
  }

  Future<void> _addContactToFamily(TaskStore store, ChatContact contact) async {
    try {
      final members = await store.repository.api.addFamilyMembers(
        actorProfile: store.owner.value,
        profiles: [contact.profileKey],
      );
      if (mounted) {
        setState(() => _familyMembers = members);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${contactLabel(contact)} добавлен в семью')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить в семью: $error')),
        );
      }
    }
  }

  Future<void> _loadPhoneContacts(TaskStore store) async {
    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.read);
      var registered = _chatContacts;
      if (status == PermissionStatus.granted) {
        final contacts = await FlutterContacts.getAll(
          properties: {ContactProperty.phone},
        );
        final phones = <String>[];
        for (final contact in contacts) {
          for (final phone in contact.phones) {
            if (phone.number.trim().isNotEmpty) {
              phones.add(phone.number);
            }
          }
        }
        registered = await store.repository.api.resolveContacts(
          actorProfile: store.owner.value,
          phones: phones,
        );
      }
      final members = await store.repository.api.familyMembers(
        actorProfile: store.owner.value,
      );
      if (mounted) {
        setState(() {
          _phoneContacts = registered;
          _familyMembers = members;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _phoneContacts = _chatContacts;
        });
      }
    }
  }

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
      setState(() {
        _isRecording = true;
        _voiceSec = 0;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording) setState(() => _voiceSec++);
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
    setState(() => _isRecording = false);
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

  Future<void> _retryPendingMessages(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    for (final entry in _chatMessagesByConversation.entries) {
      final convKey = entry.key;
      final msgs = entry.value;
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        if (m.deliveryStatus != 'sending') continue;
        if (m.senderProfile != store.owner.value) continue;
        try {
          final sent = await api.chatSendMessage(
            actorProfile: store.owner.value,
            conversationKey: convKey,
            messageType: m.messageType,
            text: m.text,
            clientMessageId: m.clientMessageId,
            attachments: m.attachments,
          );
          await db.upsertMessages([sent]);
          msgs[i] = sent.copyWith(deliveryStatus: 'sent');
          _chatMessagesByConversation[convKey] = msgs;
        } catch (_) {
          // Will retry next cycle
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// Mark locally-cached messages as delivered when they appear in a server pull
  void _markDelivered(String conversationKey, List<ChatMessage> serverMsgs) {
    final local = _chatMessagesByConversation[conversationKey];
    if (local == null) return;
    final serverIds = serverMsgs.map((m) => m.id).toSet();
    var changed = false;
    for (var i = 0; i < local.length; i++) {
      if (local[i].deliveryStatus == 'sent' &&
          serverIds.contains(local[i].id)) {
        local[i] = local[i].copyWith(deliveryStatus: 'delivered');
        changed = true;
      }
    }
    if (changed) {
      _chatMessagesByConversation[conversationKey] = local;
    }
  }

  void _onChatInputChanged(TaskStore store) {
    final text = _chatInputCtl.text.trim();
    if (text.isEmpty) return;
    if (isProjectConversation(_activeConversationKey)) return;
    // Debounce: send typing every 5 seconds max
    if (_typingSendTimer?.isActive == true) return;
    _typingSendTimer = Timer(const Duration(seconds: 5), () async {
      try {
        await store.repository.api.chatSendTyping(
          actorProfile: store.owner.value,
          conversationKey: _activeConversationKey,
        );
      } catch (_) {}
    });
  }

  Future<void> _sendTextMessage(TaskStore store) async {
    // Route to project bridge for project conversations
    if (isProjectConversation(_activeConversationKey)) {
      _sendProjectMessage();
      return;
    }

    final text = _chatInputCtl.text.trim();
    if (text.isEmpty) {
      return;
    }
    final replyTo = _replyToMessage;
    String finalText = text;
    if (replyTo != null) {
      final senderLabel = _profileLabel(replyTo.senderProfile);
      if (replyTo.messageType == 'image' ||
          replyTo.messageType == 'image_group') {
        final url = (replyTo.imageUrl ?? '').isNotEmpty
            ? replyTo.imageUrl!
            : (replyTo.attachments.isNotEmpty
                ? replyTo.attachments.first.assetUrl
                : '');
        finalText = '> $senderLabel: [photo:$url] ${replyTo.text}\n$text';
      } else if (replyTo.messageType == 'video' ||
          replyTo.messageType == 'video_group') {
        final url = (replyTo.imageUrl ?? '').isNotEmpty
            ? replyTo.imageUrl!
            : (replyTo.attachments.isNotEmpty
                ? replyTo.attachments.first.assetUrl
                : '');
        finalText = '> $senderLabel: [video:$url] ${replyTo.text}\n$text';
      } else if (replyTo.messageType == 'voice') {
        finalText = '> $senderLabel: [voice] ${replyTo.text}\n$text';
      } else if (replyTo.messageType == 'audio') {
        finalText = '> $senderLabel: [audio] ${replyTo.text}\n$text';
      } else {
        finalText =
            '> $senderLabel: ${replyTo.text.split('\n').join('\n> ')}\n$text';
      }
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    final editingId = _editingMessageId;
    final clientId = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    final replyClientId = replyTo != null
        ? 'reply-${replyTo.id}-${DateTime.now().microsecondsSinceEpoch}'
        : clientId;

    // Insert optimistic message immediately
    final optMsg = ChatMessage(
      id: editingId ?? clientId,
      conversationKey: conversationKey,
      senderProfile: actor,
      messageType: 'text',
      text: finalText,
      createdAt: nowIso,
      clientMessageId: replyClientId,
      deliveryStatus: 'sending',
    );
    final msgs = List<ChatMessage>.from(
      _chatMessagesByConversation[conversationKey] ?? const [],
    );
    if (editingId != null) {
      final idx = msgs.indexWhere((m) => m.id == editingId);
      if (idx >= 0) {
        msgs[idx] = optMsg;
      } else {
        msgs.add(optMsg);
      }
    } else {
      msgs.add(optMsg);
    }
    _chatMessagesByConversation[conversationKey] = msgs;
    _chatInputCtl.clear();
    setState(() {
      _editingMessageId = null;
      _replyToMessage = null;
    });

    // Attempt to send
    try {
      final message = editingId == null
          ? await api.chatSendMessage(
              actorProfile: actor,
              conversationKey: conversationKey,
              messageType: 'text',
              text: finalText,
              clientMessageId: replyClientId,
            )
          : await api.chatEditMessage(
              actorProfile: actor,
              messageId: editingId,
              text: text,
            );
      await db.upsertMessages([message]);

      // Update local message with server data
      final updated = List<ChatMessage>.from(
        _chatMessagesByConversation[conversationKey] ?? const [],
      );
      final idx = updated.indexWhere((m) => m.id == optMsg.id);
      if (idx >= 0) {
        updated[idx] = message.copyWith(deliveryStatus: 'sent');
      }
      _chatMessagesByConversation[conversationKey] = updated;
      if (mounted) setState(() {});
    } catch (_) {
      // Message stays in 'sending' state — retry on next sync
    }
  }

  Future<void> _shareMessage(TaskStore store, ChatMessage message) async {
    if (message.isDeleted) return;
    final allContacts = _allKnownContacts(store);
    // Build list of unique contacts excluding self
    final targets =
        allContacts.where((c) => c.profileKey != store.owner.value).toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет контактов для пересылки')),
        );
      }
      return;
    }
    final selected = await showDialog<ChatContact>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Поделиться с...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: targets.length,
            itemBuilder: (_, i) {
              final contact = targets[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(contactLabel(contact)),
                subtitle: contact.phone.isNotEmpty ? Text(contact.phone) : null,
                onTap: () => Navigator.pop(ctx, contact),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    // Open conversation with selected contact and forward message
    var conversationKey = selected.conversationKey;
    if (conversationKey.isEmpty) {
      final members = [store.owner.value, selected.profileKey]..sort();
      conversationKey = 'dm:${members[0]}:${members[1]}';
    }
    try {
      final api = store.repository.api;
      final senderLabel = profileLabel(message.senderProfile);
      // Send as forwarded message
      String shareText = '';
      if (message.messageType == 'text') {
        shareText = '↪ $senderLabel: ${message.text}';
      } else if (message.messageType == 'sticker') {
        await api.chatSendMessage(
          actorProfile: store.owner.value,
          conversationKey: conversationKey,
          messageType: 'sticker',
          stickerId: message.stickerId ?? '',
          text: '↪ $senderLabel: Стикер',
        );
      } else if (message.messageType == 'image' ||
          message.messageType == 'image_group') {
        final atts = message.attachments.isNotEmpty
            ? message.attachments
            : (message.imageUrl != null && message.imageUrl!.isNotEmpty
                ? [
                    ChatAttachment(
                        kind: 'image',
                        assetUrl: message.imageUrl!,
                        imageMeta: message.imageMeta,
                        sortOrder: 0)
                  ]
                : const <ChatAttachment>[]);
        if (atts.isNotEmpty) {
          await api.chatSendMessage(
            actorProfile: store.owner.value,
            conversationKey: conversationKey,
            messageType: atts.length == 1 ? 'image' : 'image_group',
            attachments: atts,
            text: message.text.isNotEmpty
                ? '↪ $senderLabel: ${message.text}'
                : '↪ $senderLabel: Фото',
          );
        }
      }
      if (shareText.isNotEmpty) {
        await api.chatSendMessage(
          actorProfile: store.owner.value,
          conversationKey: conversationKey,
          messageType: 'text',
          text: shareText,
        );
      }
      // Navigate to the conversation
      setState(() => _activeConversationKey = conversationKey);
      // Mark messages as read
      store.repository.api
          .chatMarkRead(
            actorProfile: store.owner.value,
            conversationKey: conversationKey,
          )
          .catchError((_) {});
      await _refreshConversation(store, conversationKey,
          useNetwork: true, quiet: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Переслано → ${contactLabel(selected)}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка пересылки: $error')),
        );
      }
    }
  }

  Future<void> _editChatMessage(ChatMessage message) async {
    setState(() {
      _editingMessageId = message.id;
      _chatInputCtl.text = message.text;
      _chatInputCtl.selection = TextSelection.collapsed(
        offset: _chatInputCtl.text.length,
      );
    });
  }

  Future<void> _deleteChatMessage(TaskStore store, ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text('Сообщение будет удалено у всех участников.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    try {
      final updated = await store.repository.api.chatDeleteMessage(
        actorProfile: store.owner.value,
        messageId: message.id,
      );
      await store.repository.db.upsertMessages([updated]);
      await _refreshConversation(
        store,
        message.conversationKey,
        useNetwork: true,
        quiet: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $error')),
      );
    }
  }

  Future<void> _openMessageActions(
    TaskStore store,
    ChatMessage message,
  ) async {
    if (message.isDeleted) {
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: ['👍', '❤️', '😂', '🔥', '🙏'].map((reaction) {
                  return ActionChip(
                    label: Text(reaction),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop('react:$reaction'),
                  );
                }).toList(),
              ),
              if (message.myReaction != null)
                ListTile(
                  leading: const Icon(Icons.close),
                  title: const Text('Убрать реакцию'),
                  onTap: () => Navigator.of(sheetContext).pop('react:'),
                ),
              if (message.messageType == 'text' &&
                  message.senderProfile == store.owner.value)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Ответить'),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Поделиться'),
                onTap: () => Navigator.of(sheetContext).pop('share'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Удалить'),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            ],
          ),
        );
      },
    );
    if ((action ?? '').startsWith('react:')) {
      await _setMessageReaction(
        store,
        message,
        action!.substring('react:'.length),
      );
    } else if (action == 'edit') {
      await _editChatMessage(message);
    } else if (action == 'reply') {
      setState(() {
        _replyToMessage = message;
      });
    } else if (action == 'share') {
      await _shareMessage(store, message);
    } else if (action == 'delete') {
      await _deleteChatMessage(store, message);
    }
  }

  Future<void> _setMessageReaction(
    TaskStore store,
    ChatMessage message,
    String reaction,
  ) async {
    try {
      final updated = await store.repository.api.chatSetReaction(
        actorProfile: store.owner.value,
        messageId: message.id,
        reaction: reaction,
      );
      await store.repository.db.upsertMessages([updated]);
      await _refreshConversation(
        store,
        message.conversationKey,
        useNetwork: true,
        quiet: true,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка реакции: $error')),
        );
      }
    }
  }

  Future<void> _sendBuiltInSticker(
    TaskStore store,
    StickerItem sticker,
  ) async {
    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    try {
      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: 'sticker',
        stickerId: sticker.stickerId,
        clientMessageId: 'st-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.upsertMessages([message]);
      await _refreshConversation(
        store,
        conversationKey,
        useNetwork: true,
        quiet: true,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки стикера: $error')),
      );
    }
  }

  Future<void> _openManageGroupSheet(
      TaskStore store, ChatConversation conv) async {
    final members = List<String>.from(conv.members);
    final canManage = conv.kind == 'group' ||
        conv.conversationKey == 'group:common' ||
        conv.conversationKey.startsWith('grp:');

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    conv.title.isNotEmpty ? conv.title : 'Группа',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (canManage) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final title = await _promptGroupTitle(
                                conv.title.isNotEmpty ? conv.title : 'Группа',
                              );
                              if (title == null || title.trim().isEmpty) {
                                return;
                              }
                              try {
                                await store.repository.api.renameGroup(
                                  actorProfile: store.owner.value,
                                  conversationKey: conv.conversationKey,
                                  title: title.trim(),
                                );
                                if (mounted && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                  await _refreshChatBootstrap(store);
                                }
                              } catch (error) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ошибка: $error')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Назвать'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await _confirmDeleteGroup(conv);
                              if (ok != true) {
                                return;
                              }
                              try {
                                await store.repository.api.deleteGroup(
                                  actorProfile: store.owner.value,
                                  conversationKey: conv.conversationKey,
                                );
                                if (mounted && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                  await _removeLocalConversation(
                                    store,
                                    conv.conversationKey,
                                  );
                                  await _refreshChatBootstrap(store);
                                }
                              } catch (error) {
                                if (mounted && sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                  await _removeLocalConversation(
                                    store,
                                    conv.conversationKey,
                                  );
                                  if (!mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Группа удалена из локального списка',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Удалить'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final profile in members)
                          ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(_profileLabel(profile)),
                            trailing: canManage && profile != store.owner.value
                                ? IconButton(
                                    icon: const Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.red),
                                    onPressed: () async {
                                      setSheetState(
                                          () => members.remove(profile));
                                      try {
                                        await store.repository.api
                                            .removeGroupMember(
                                          actorProfile: store.owner.value,
                                          conversationKey: conv.conversationKey,
                                          profile: profile,
                                        );
                                      } catch (_) {}
                                    },
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  if (canManage)
                    ListTile(
                      leading: const Icon(Icons.person_add),
                      title: const Text('Добавить участника'),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await _addMemberToGroup(store, conv);
                      },
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<String?> _promptGroupTitle(String initial) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            hintText: 'Например: Семья',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDeleteGroup(ChatConversation conv) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: Text(
          'Группа "${conv.title.isNotEmpty ? conv.title : 'Группа'}" исчезнет у всех участников вместе с перепиской.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMemberToGroup(TaskStore store, ChatConversation conv) async {
    final available = _chatContacts
        .where((c) => !conv.members.contains(c.profileKey))
        .toList();
    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступных контактов')),
        );
      }
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Выбрать участника'),
        children: available
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c.profileKey),
                  child: Text(contactLabel(c)),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      await store.repository.api.addGroupMember(
        actorProfile: store.owner.value,
        conversationKey: conv.conversationKey,
        profile: selected,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_profileLabel(selected)} добавлен')),
        );
      }
      await _refreshChatBootstrap(store);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $error')),
        );
      }
    }
  }

  Future<void> _pickAndSendDocument(TaskStore store) async {
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
            const SnackBar(content: Text('Не удалось прочитать файл')),
          );
        }
        return;
      }

      final filePath = file.path!;
      final fileBytes = await File(filePath).readAsBytes();
      final fileName = file.name;
      const maxBytes = 50 * 1024 * 1024; // 50 MB
      if (fileBytes.length > maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Файл слишком большой. Максимум 50 МБ.')),
          );
        }
        return;
      }

      final conversationKey = _activeConversationKey;
      final owner = store.owner.value;
      if (conversationKey.isEmpty || owner.isEmpty) return;

      final clientId = 'doc-${DateTime.now().microsecondsSinceEpoch}';
      final optimisticMsg = ChatMessage(
        id: clientId,
        conversationKey: conversationKey,
        senderProfile: owner,
        messageType: 'file',
        text: '',
        createdAt: DateTime.now().toIso8601String(),
        attachments: [
          ChatAttachment(
            kind: 'file',
            assetUrl: filePath,
            imageMeta: {
              'original_name': fileName,
              'size_bytes': fileBytes.length,
            },
            sortOrder: 0,
          ),
        ],
        isUploading: true,
        uploadProgress: 0.0,
        clientMessageId: clientId,
        deliveryStatus: 'sending',
      );

      final msgs = _chatMessagesByConversation[conversationKey] ?? [];
      msgs.add(optimisticMsg);
      _chatMessagesByConversation[conversationKey] = msgs;
      if (mounted) setState(() {});

      final api = store.repository.api;
      final uploadResult = await api.chatUploadDocument(
        actorProfile: owner,
        bytes: fileBytes,
        filename: fileName,
        onProgress: (progress) {
          _updateUploadProgress(conversationKey, clientId, 0, 1, progress);
        },
      );

      final message = await api.chatSendMessage(
        actorProfile: owner,
        conversationKey: conversationKey,
        messageType: 'file',
        text: '',
        attachments: [
          ChatAttachment(
            kind: 'file',
            assetUrl: uploadResult.assetUrl,
            imageMeta: uploadResult.imageMeta,
            sortOrder: 0,
          ),
        ],
        clientMessageId: clientId,
      );

      _replaceOptimisticMessages(conversationKey, clientId, [message]);
      final db = store.repository.db;
      await db.upsertMessages([message]);
      if (mounted) setState(() {});
    } catch (error) {
      final conversationKey = _activeConversationKey;
      if (conversationKey.isNotEmpty) {
        final msgs = _chatMessagesByConversation[conversationKey];
        if (msgs != null) {
          msgs.removeWhere((m) => m.isUploading && m.messageType == 'file');
          _chatMessagesByConversation[conversationKey] = msgs;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки документа: $error')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _sendPhotos(
    TaskStore store, {
    required ImageSource source,
    bool allowMultiple = false,
  }) async {
    final picked = <XFile>[];
    if (allowMultiple && source == ImageSource.gallery) {
      picked.addAll(
        await _imagePicker.pickMultiImage(imageQuality: 80, maxWidth: 1600),
      );
    } else {
      final one = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (one != null) {
        picked.add(one);
      }
    }
    if (picked.isEmpty) {
      return;
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    if (conversationKey.isEmpty) return;

    // Optional caption
    String caption = '';
    if (mounted) {
      final captionCtl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Подпись к фото'),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Добавить подпись (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Пропустить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      if (result != null) caption = result;
    }

    // Create one optimistic bubble with local previews and shared progress.
    final msgType = picked.length == 1 ? 'image' : 'image_group';
    final clientId = 'img-${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();
    final totalCount = picked.length;
    final localAttachments = [
      for (var i = 0; i < totalCount; i++)
        ChatAttachment(
          kind: 'image',
          assetUrl: picked[i].path,
          imageMeta: const {'local_preview': true},
          sortOrder: i,
        ),
    ];
    final optMsg = ChatMessage(
      id: clientId,
      conversationKey: conversationKey,
      senderProfile: actor,
      messageType: msgType,
      text: caption,
      createdAt: nowIso,
      attachments: localAttachments,
      clientMessageId: clientId,
      isUploading: true,
      uploadProgress: 0.0,
      deliveryStatus: 'sending',
    );
    final msgs = List<ChatMessage>.from(
      _chatMessagesByConversation[conversationKey] ?? const [],
    );
    msgs.add(optMsg);
    _chatMessagesByConversation[conversationKey] = msgs;
    if (mounted) setState(() {});

    // Upload photos one by one with progress
    try {
      final attachments = <ChatAttachment>[];
      for (var i = 0; i < picked.length; i++) {
        final file = picked[i];
        final bytes = await file.readAsBytes();

        // Update progress: reading done, uploading
        _updateUploadProgress(conversationKey, clientId, i, totalCount, 0.1);

        final uploaded = await api.chatUploadMedia(
          actorProfile: actor,
          bytes: bytes,
          filename: file.name,
          onProgress: (progress) {
            final p = 0.1 + (progress * 0.6);
            _updateUploadProgress(conversationKey, clientId, i, totalCount, p);
          },
        );

        _updateUploadProgress(conversationKey, clientId, i, totalCount, 0.8);
        attachments.add(ChatAttachment(
          kind: 'image',
          assetUrl: uploaded.assetUrl,
          imageMeta: uploaded.imageMeta,
          sortOrder: i,
        ));
        _updateUploadProgress(conversationKey, clientId, i, totalCount, 0.9);
      }

      // Send the actual message
      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: msgType,
        text: caption,
        attachments: attachments,
        clientMessageId: clientId,
      );

      // Remove optimistic messages, add real one
      _replaceOptimisticMessages(conversationKey, clientId, [message]);
      await db.upsertMessages([message]);
      if (mounted) setState(() {});
    } catch (error) {
      // Mark optimistic messages as failed
      _failOptimisticMessages(conversationKey, clientId, error.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $error')),
        );
      }
    }
  }

  /// Update upload progress for an optimistic message
  void _updateUploadProgress(String conversationKey, String clientId, int index,
      int total, double progress) {
    final msgs = _chatMessagesByConversation[conversationKey];
    if (msgs == null) return;
    final itemProgress = progress.clamp(0.0, 1.0);
    final overall = ((index + itemProgress) / total).clamp(0.0, 1.0);
    for (var i = 0; i < msgs.length; i++) {
      if (msgs[i].clientMessageId == clientId) {
        msgs[i] = msgs[i].copyWith(
          isUploading: true,
          uploadProgress: overall,
          deliveryStatus: 'sending',
        );
        _chatMessagesByConversation[conversationKey] = msgs;
        if (mounted) setState(() {});
        return;
      }
    }
  }

  /// Replace optimistic messages with the real server message
  void _replaceOptimisticMessages(
      String conversationKey, String clientId, List<ChatMessage> realMsgs) {
    final msgs = _chatMessagesByConversation[conversationKey];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.clientMessageId == clientId);
    msgs.addAll(realMsgs);
    _chatMessagesByConversation[conversationKey] = msgs;
  }

  /// Mark optimistic messages as failed (remove them)
  void _failOptimisticMessages(
      String conversationKey, String clientId, String error) {
    final msgs = _chatMessagesByConversation[conversationKey];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.clientMessageId == clientId);
    _chatMessagesByConversation[conversationKey] = msgs;
    debugPrint('Upload failed ($clientId): $error');
    if (mounted) setState(() {});
  }

  Future<void> _pickAndSendVideo(TaskStore store) async {
    final video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
    );
    if (video == null) return;

    // Check file size
    try {
      final sizeBytes = await video.length();
      const maxBytes = 190 * 1024 * 1024;
      if (sizeBytes > maxBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Видео слишком большое. Максимум 190 МБ.')),
          );
        }
        return;
      }
    } catch (_) {}

    // Optional caption
    String caption = '';
    if (mounted) {
      final captionCtl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Подпись к видео'),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Добавить подпись (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Пропустить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
      if (result != null) caption = result;
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    if (conversationKey.isEmpty) return;

    final clientId = 'vid-${DateTime.now().microsecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();

    // Create optimistic message immediately
    final optMsg = ChatMessage(
      id: '$clientId-0',
      conversationKey: conversationKey,
      senderProfile: actor,
      messageType: 'video',
      text: caption,
      createdAt: nowIso,
      clientMessageId: clientId,
      isUploading: true,
      uploadProgress: 0.0,
    );
    final msgs = List<ChatMessage>.from(
      _chatMessagesByConversation[conversationKey] ?? const [],
    );
    msgs.add(optMsg);
    _chatMessagesByConversation[conversationKey] = msgs;
    if (mounted) setState(() {});

    try {
      // Read file
      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.0);
      final bytes = await video.readAsBytes();

      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.1);

      // Upload with progress
      final uploaded = await api.chatUploadMedia(
        actorProfile: actor,
        bytes: bytes,
        filename: video.name,
        onProgress: (progress) {
          final p = 0.1 + (progress * 0.7);
          _updateUploadProgress(conversationKey, clientId, 0, 1, p);
        },
      );

      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.85);
      final meta = Map<String, dynamic>.from(uploaded.imageMeta);

      final attachment = ChatAttachment(
        kind: 'video',
        assetUrl: uploaded.assetUrl,
        imageMeta: meta,
        sortOrder: 0,
      );

      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.95);

      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: 'video',
        text: caption,
        attachments: [attachment],
        clientMessageId: clientId,
      );

      _replaceOptimisticMessages(conversationKey, clientId, [message]);
      await db.upsertMessages([message]);
      if (mounted) setState(() {});
    } catch (error) {
      _failOptimisticMessages(conversationKey, clientId, error.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки видео: $error')),
        );
      }
    }
  }

  Future<void> _openAttachMenu(TaskStore store) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Галерея'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendPhotos(store,
                      source: ImageSource.gallery, allowMultiple: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Камера'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendPhotos(store, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Видео'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendVideo(store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Документ'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendDocument(store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Стикер'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openStickerSheet(store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Файлы проекта'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  final project =
                      _projectByConversationKey(_activeConversationKey);
                  if (project != null) {
                    _openProjectFileManager(project);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openStickerSheet(TaskStore store) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Стикеры',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        await _sendPhotos(
                          store,
                          source: ImageSource.gallery,
                          allowMultiple: true,
                        );
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Мой стикер'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      for (final pack in _chatStickerPacks) ...[
                        Text(
                          pack.title.isEmpty ? pack.packKey : pack.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in pack.items)
                              OutlinedButton(
                                onPressed: () async {
                                  Navigator.of(sheetContext).pop();
                                  await _sendBuiltInSticker(store, item);
                                },
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: _stickerPreview(item),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleIncomingCall(CallSession session) {
    if (!mounted) return;
    final peerLabel = _profileLabel(session.callerProfile);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          callService: _callService!,
          session: session,
          isIncoming: true,
          peerLabel: peerLabel,
          onCallFinished: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _startCallOutgoing({String callType = 'audio'}) {
    if (!mounted || _store == null || _activeConversationKey.isEmpty) return;
    final store = _store!;
    final api = store.repository.api;
    final actor = store.owner.value;

    _replaceCallService(api: api, actorProfile: actor);

    final conv = _chatConversations.firstWhere(
      (c) => c.conversationKey == _activeConversationKey,
      orElse: () => ChatConversation(
        conversationKey: _activeConversationKey,
        kind: 'direct',
        title: '',
        members: [],
      ),
    );

    final peerProfile = conv.members.isNotEmpty
        ? conv.members.firstWhere((m) => m != actor, orElse: () => actor)
        : '';

    final session = CallSession(
      sessionId: '',
      callerProfile: actor,
      calleeProfile: peerProfile,
      conversationKey: _activeConversationKey,
      callType: callType,
      status: 'ringing',
      createdAt: DateTime.now().toIso8601String(),
    );

    final peerLabel = _profileLabel(peerProfile);

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          callService: _callService!,
          session: session,
          isIncoming: false,
          peerLabel: peerLabel,
          onCallFinished: () {
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Widget _buildMessengerPage(TaskStore store, {required bool compact}) {
    final messages = _chatMessagesByConversation[_activeConversationKey] ??
        const <ChatMessage>[];

    if (_chatLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (isProjectConversation(_activeConversationKey)) {
      return _buildProjectChatView(store, compact: compact);
    }

    return MessengerPage(
      conversations: _chatConversations,
      contacts: _phoneContacts.isEmpty ? _chatContacts : _phoneContacts,
      projects: _projectContacts,
      messages: messages,
      activeConversationKey: _activeConversationKey,
      owner: store.owner.value,
      compact: compact,
      chatInputController: _chatInputCtl,
      replyToMessage: _replyToMessage,
      editingMessageId: _editingMessageId,
      isRecording: _isRecording,
      conversationLabel: _conversationLabel,
      contactLabel: contactLabel,
      chatMessageText: _chatMessageText,
      profileLabel: _profileLabel,
      stickerAssetFor: _chatStickerAssetUrl,
      imageUrlFor: _chatImageUrl,
      avatarForContact: _avatarForProfile,
      onRefreshContacts: () => _refreshMessengerContacts(store),
      onCreateGroup: () => _openCreateGroupSheet(store),
      onAddContactToFamily: (contact) => _addContactToFamily(store, contact),
      onOpenDirectContact: (contact) => _openDirectContact(store, contact),
      onOpenProjectContact: (project) => _openProjectContact(store, project),
      onOpenBridgeSettings: _openBridgeSettings,
      onBackToContacts: () => setState(() => _activeConversationKey = ''),
      onOpenConversation: (conversationKey) =>
          _openConversation(store, conversationKey),
      onOpenMessageActions: (message) => _openMessageActions(store, message),
      onImageTap: _openPhotoViewer,
      onClearReply: () => setState(() => _replyToMessage = null),
      onCancelEdit: () {
        setState(() {
          _editingMessageId = null;
          _chatInputCtl.clear();
        });
      },
      onOpenAttachMenu: () => _openAttachMenu(store),
      onManageGroup: (conv) => _openManageGroupSheet(store, conv),
      onCallTap: () => _startCallOutgoing(callType: 'audio'),
      onVideoCallTap: () => _startCallOutgoing(callType: 'video'),
      typingUsers: _typingUsers,
      onStartRecord: () => _startRecord(store),
      onStopRecord: () => _stopRecord(store),
      onSendText: () => _sendTextMessage(store),
    );
  }

  Widget _buildProjectChatView(TaskStore store, {required bool compact}) {
    final project = _projectByConversationKey(_activeConversationKey);
    if (project == null) {
      return const Center(child: Text('Проект не найден'));
    }

    return ProjectChatView(
      project: project,
      bridge: _projectBridge,
      messages: _projectMessages,
      chatInputController: _chatInputCtl,
      onBack: () {
        setState(() => _activeConversationKey = '');
        // Keep bridge connection alive so session persists.
        // Messages are already saved to DB and will be restored on re-entry.
      },
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
      setState(() {
        _projectMessages.add(sentMsg);
      });
      if (store != null) {
        _saveProjectMessageToDb(store.repository.db, sentMsg);
      }
    }
  }

  void _openProjectFileManager(ProjectContact project) {
    // Request file tree, then show bottom sheet
    _projectFiles = [];
    _projectFileTreePath = '';
    _projectFilesLoading = true;
    _projectBridge?.requestFileTree();
    setState(() {
      _projectMessages.add(BridgeMessage(
        type: 'status',
        text: 'Запрашиваю файлы проекта...',
      ));
    });

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
                setState(() {
                  _projectFileTreePath = path;
                  _projectFiles = [];
                  _projectFilesLoading = true;
                });
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
                final link = 'Файл: $fullPath';
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
                setState(() {
                  _projectFileTreePath = filePath;
                  _projectFiles = [];
                  _projectFilesLoading = true;
                });
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
    final ctl = ValueNotifier<String>('Загрузка содержимого...');
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
            child: const Text('Закрыть'),
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
                            path.isNotEmpty ? path.split('/').last : 'Файл',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (!hasError)
                          IconButton(
                            tooltip: 'Копировать всё',
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: content));
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                    content: Text('Скопировано в буфер'),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                          ),
                        IconButton(
                          tooltip: 'Закрыть',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (path.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(path,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5))),
                    ),
                  const Divider(),
                  Expanded(
                    child: hasError
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(content.isEmpty
                                  ? 'Файл пуст'
                                  : content.replaceFirst('Error: ', '')),
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
    setState(() {
      _projectMessages.add(BridgeMessage(
        type: ok ? 'status' : 'error',
        text: ok
            ? 'Команда запуска bridge отправлена'
            : 'Не удалось отправить команду запуска bridge',
      ));
    });
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
    setState(() {
      _projectMessages
        ..clear()
        ..add(BridgeMessage(
          type: 'status',
          text: 'Создаю новую сессию...',
        ));
    });
  }

  void _stopProjectPrompt() {
    _projectBridge?.stopCurrentPrompt();
    if (!mounted) {
      return;
    }
    setState(() {
      _projectMessages.add(BridgeMessage(
        type: 'status',
        text: 'Команда остановки отправлена',
      ));
    });
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
      final captionCtl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Комментарий к фото'),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Промт для DeepSeek после загрузки (необязательно)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Только сохранить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: const Text('Отправить'),
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
      } catch (_) {
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
          setState(() {
            _projectMessages.add(BridgeMessage(
              type: 'sent_image',
              text: caption,
              imageBase64: base64Encode(bytes),
              imageMimeType: _projectImageMime(file),
              imageFilename: file.name,
            ));
          });
        }
      } else {
        failed += 1;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (sent > 0) {
        _projectMessages.add(BridgeMessage(
          type: 'send',
          text: 'Фото сохранено в vision: $sent',
        ));
      }
      if (failed > 0 || sent == 0) {
        _projectMessages.add(BridgeMessage(
          type: 'error',
          text: sent == 0
              ? 'Фото не отправлено. Проверьте соединение или размер файла.'
              : 'Не отправлено фото: $failed',
        ));
      }
    });
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
            const SnackBar(content: Text('Не удалось прочитать файл')),
          );
        }
        return;
      }

      final filePath = file.path!;
      final fileBytes = await File(filePath).readAsBytes();
      if (fileBytes.length > 15 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Файл слишком большой. Максимум 15 МБ.')),
          );
        }
        return;
      }

      // Prompt for caption
      String caption = '';
      if (mounted) {
        final captionCtl = TextEditingController();
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Комментарий к документу'),
            content: TextField(
              controller: captionCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Промт для DeepSeek после загрузки (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Только сохранить'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
                child: const Text('Отправить'),
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
        setState(() {
          _projectMessages.add(BridgeMessage(
            type: 'send',
            text: '📎 Документ: ${file.name}',
            projectId: _projectByConversationKey(_activeConversationKey)?.id ?? '',
            sessionId: _activeProjectSessionId ?? '',
          ));
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки документа: $error')),
        );
      }
    }
  }

  String guessMimeType(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt': return 'application/vnd.ms-powerpoint';
      case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'png': return 'image/png';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      case 'txt': return 'text/plain';
      case 'csv': return 'text/csv';
      case 'zip': return 'application/zip';
      case 'rar': return 'application/vnd.rar';
      case '7z': return 'application/x-7z-compressed';
      case 'mp3': return 'audio/mpeg';
      case 'mp4': return 'video/mp4';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _openBridgeSettings() async {
    final ctl = TextEditingController(
      text: await ProjectBridgeService.getServerAddress(),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Сервер проектов'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'IP-адрес и порт ПК, на котором запущен project_bridge.py',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                decoration: const InputDecoration(
                  labelText: 'Адрес',
                  hintText: '192.168.1.5:9876',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Отмена'),
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
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  String _conversationLabel(ChatConversation conversation, String actor) {
    if (conversation.kind == 'group' ||
        conversation.conversationKey == 'group:common') {
      final title = conversation.title.trim();
      return title.isNotEmpty ? title : 'Общий';
    }
    final peer = conversation.members.firstWhere(
      (item) => item != actor,
      orElse: () => '',
    );
    if (peer.isNotEmpty) {
      return _profileLabel(peer);
    }

    final fromContacts = _chatContacts
        .where((item) => item.conversationKey == conversation.conversationKey)
        .toList();
    if (fromContacts.isNotEmpty) {
      return contactLabel(fromContacts.first);
    }
    return conversation.conversationKey;
  }

  List<ChatContact> _allKnownContacts(TaskStore store) {
    final seen = <String>{};
    final result = <ChatContact>[];
    final self = ChatContact(
      profileKey: store.owner.value,
      displayName: _profileLabel(store.owner.value),
      phone: '',
      conversationKey: '',
    );
    result.add(self);
    seen.add(self.profileKey);
    for (final m in _familyMembers) {
      if (seen.add(m.profileKey)) result.add(m);
    }
    for (final c in _chatContacts) {
      if (seen.add(c.profileKey)) result.add(c);
    }
    for (final c in _phoneContacts) {
      if (seen.add(c.profileKey)) result.add(c);
    }
    return result;
  }

  String contactLabel(ChatContact contact) {
    if (contact.displayName.trim().isNotEmpty) {
      return contact.displayName.trim();
    }
    return _profileLabel(contact.profileKey);
  }

  void _openProfile() {
    final store = _store;
    if (store == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          api: store.repository.api,
          displayName: _currentProfileDisplayName,
          phone: _currentProfilePhone,
          profileKey: store.owner.value,
          avatarUrl: _currentProfileAvatarUrl,
          onAvatarChanged: (url) {
            setState(() => _currentProfileAvatarUrl = url);
          },
          onDisplayNameChanged: (name) {
            setState(() => _currentProfileDisplayName = name);
          },
        ),
      ),
    );
  }

  String? _avatarForProfile(String profile) {
    final store = _store;
    if (store == null) return null;
    // Return own avatar for current user
    if (profile == store.owner.value) return _currentProfileAvatarUrl;
    final cached = _profileAvatarUrls[profile];
    if (cached != null && cached.isNotEmpty) return cached;
    // Try to find avatar from loaded contacts
    for (final contact in [..._chatContacts, ..._familyMembers]) {
      if (contact.profileKey == profile &&
          contact.avatarUrl != null &&
          contact.avatarUrl!.isNotEmpty) {
        _profileAvatarUrls[profile] = contact.avatarUrl!;
        return contact.avatarUrl;
      }
    }
    return null;
  }

  Future<void> _saveAvatarUrlsFromContacts(List<ChatContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    for (final contact in contacts) {
      final url = contact.avatarUrl;
      if (url != null && url.isNotEmpty) {
        await prefs.setString('avatar_${contact.profileKey}', url);
      }
    }
  }

  Future<void> _loadProfileAvatars(Iterable<String> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in profiles) {
      final profile = raw.trim();
      if (profile.isEmpty) continue;
      final avatar = prefs.getString('avatar_$profile')?.trim() ?? '';
      if (avatar.isNotEmpty) {
        _profileAvatarUrls[profile] = avatar;
      }
    }
  }

  String _profileLabel(String profile) {
    for (final contact in [
      ..._chatContacts,
      ..._phoneContacts,
      ..._familyMembers
    ]) {
      if (contact.profileKey == profile &&
          contact.displayName.trim().isNotEmpty) {
        return contact.displayName.trim();
      }
    }
    if (profile == (_store?.owner.value ?? '') &&
        _currentProfileDisplayName.trim().isNotEmpty) {
      return _currentProfileDisplayName.trim();
    }
    return profileLabel(profile);
  }

  String _chatMessageText(ChatMessage message) {
    if (message.isDeleted) {
      return 'Сообщение удалено';
    }
    if (message.messageType == 'sticker') {
      final id = message.stickerId ?? '';
      if (id.isEmpty) {
        return '🙂';
      }
      for (final pack in _chatStickerPacks) {
        for (final item in pack.items) {
          if (item.stickerId == id) {
            return item.title.isEmpty ? '🙂' : item.title;
          }
        }
      }
      return '🙂';
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      return message.text.isNotEmpty ? message.text : 'Изображение';
    }
    if (message.messageType == 'voice') {
      final ms = (message.imageMeta['duration_ms'] as int?) ?? 0;
      final d = Duration(milliseconds: ms);
      return '🎤 ${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    if (message.messageType == 'video' ||
        message.messageType == 'video_group') {
      return message.text.isNotEmpty ? message.text : 'Видео';
    }
    if (message.messageType == 'audio') {
      return message.text.isNotEmpty ? message.text : 'Аудио';
    }
    return message.text;
  }

  String _chatStickerAssetUrl(ChatMessage message) {
    if (message.messageType != 'sticker') {
      return '';
    }
    final id = message.stickerId ?? '';
    if (id.isEmpty) {
      return '';
    }
    for (final pack in _chatStickerPacks) {
      for (final item in pack.items) {
        if (item.stickerId == id) {
          return _absoluteAssetUrl(item.assetUrl);
        }
      }
    }
    return '';
  }

  String _chatImageUrl(ChatMessage message) {
    if (message.messageType != 'image' && message.messageType != 'voice') {
      return '';
    }
    return _absoluteAssetUrl(message.imageUrl ?? '');
  }

  Future<void> _saveImageToGallery(String url) async {
    try {
      const channel = MethodChannel('family_todo_mobile/share');
      await channel.invokeMethod<bool>('saveImage', {'url': url});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Фото сохранено в галерею')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить фото')),
        );
      }
    }
  }

  void _openPhotoViewer(ChatMessage message, int initialIndex) {
    showChatPhotoViewer(
      context: context,
      urls: _messageImageUrls(message),
      initialIndex: initialIndex,
      onSaveImage: _saveImageToGallery,
    );
  }

  List<String> _messageImageUrls(ChatMessage message) {
    final attachments = message.attachments
        .where((item) => item.kind == 'image' && item.assetUrl.isNotEmpty)
        .map((item) => _absoluteAssetUrl(item.assetUrl))
        .where((item) => item.isNotEmpty)
        .toList();
    if (attachments.isNotEmpty) {
      return attachments;
    }
    final single = _chatImageUrl(message);
    return single.isEmpty ? const [] : [single];
  }

  Widget _stickerPreview(StickerItem item) {
    final url = _absoluteAssetUrl(item.assetUrl);
    if (url.isEmpty || url.startsWith('emoji://')) {
      return Center(child: Text(item.title));
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Text(
          item.title.isEmpty ? '🙂' : item.title,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String _absoluteAssetUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    if (!value.startsWith('/')) {
      return value;
    }
    final baseUrl = _store?.repository.api.baseUrl.trim() ?? '';
    if (baseUrl.isEmpty) {
      return value;
    }
    return '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$value';
  }

  bool sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.createdAt != right.createdAt ||
          left.messageType != right.messageType ||
          left.text != right.text ||
          left.imageUrl != right.imageUrl ||
          left.stickerId != right.stickerId ||
          left.attachments.length != right.attachments.length ||
          left.reactions.length != right.reactions.length ||
          left.myReaction != right.myReaction ||
          left.editedAt != right.editedAt ||
          left.deletedAt != right.deletedAt) {
        return false;
      }
    }
    return true;
  }



  Future<void> _openTaskEditor(
    TaskStore store, {
    TaskItem? existing,
    bool forceFamily = false,
  }) async {
    await showTaskEditorSheet(
      context: context,
      store: store,
      knownContacts: _allKnownContacts(store),
      contactLabel: contactLabel,
      dateKey: dateKey,
      existing: existing,
      forceFamily: forceFamily,
      onSaved: () => _safeSyncDelta(store, showErrors: true),
    );
  }

  Future<void> _setDesktopThemeMode(String mode) async {
    final service = _desktopThemeService;
    if (service == null) {
      return;
    }
    await service.setMode(mode);
  }

  Future<void> _setDesktopThemeScheme(String scheme) async {
    final service = _desktopThemeService;
    if (service == null) {
      return;
    }
    await service.setScheme(scheme);
  }

  Future<void> _toggleVoiceHost(TaskStore store, bool enabled) async {
    final host = _desktopProcessHostService;
    if (host == null) {
      return;
    }
    if (enabled) {
      await host.startVoice();
      return;
    }
    await host.stopVoice();
  }

  Future<void> _moveToDate(
      TaskStore store, TaskItem item, DateTime target) async {
    await store.moveToDate(item, dateKey(target));
    await _safeSyncDelta(store, showErrors: true);
  }

  DateTime _firstVisibleMonthDate(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday;
    final shift = weekday - DateTime.monday;
    return first.subtract(Duration(days: shift));
  }

  List<DateTime> _monthGrid(DateTime month) {
    final start = _firstVisibleMonthDate(month);
    return List<DateTime>.generate(
      42,
      (index) => start.add(Duration(days: index)),
    );
  }

  Widget _themeMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'Цветовая схема',
      icon: const Icon(Icons.palette_outlined),
      initialValue: widget.selectedThemeKey,
      onSelected: widget.onThemeChanged,
      itemBuilder: (context) {
        return [
          for (final option in appThemeOptions)
            PopupMenuItem<String>(
              value: option.key,
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: option.seed,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(option.name)),
                  if (option.key == widget.selectedThemeKey)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ValueListenableBuilder<bool>(
      valueListenable: store.loading,
      builder: (context, loading, _) {
        return ValueListenableBuilder<String>(
          valueListenable: store.owner,
          builder: (context, owner, __) {
            return ValueListenableBuilder<DateTime>(
              valueListenable: store.selectedDate,
              builder: (context, selectedDate, ___) {
                final selectedDateKey = dateKey(selectedDate);
                if (_isDesktopWindows) {
                  return _buildDesktopShell(
                    store: store,
                    loading: loading,
                    owner: owner,
                    selectedDate: selectedDate,
                    selectedDateKey: selectedDateKey,
                  );
                }
                return Scaffold(
                  appBar: AppBar(
                    leading: IconButton(
                      tooltip: 'Профиль',
                      icon: const Icon(Icons.person_outline),
                      onPressed: _openProfile,
                    ),
                    actions: [
                      _themeMenuButton(),
                      ValueListenableBuilder<bool>(
                        valueListenable: store.canUndo,
                        builder: (context, canUndo, _) {
                          return IconButton(
                            tooltip: 'Откатить последнее действие',
                            onPressed: canUndo
                                ? () async {
                                    final messenger =
                                        ScaffoldMessenger.of(this.context);
                                    final ok = await store.undoLastAction();
                                    if (!mounted) {
                                      return;
                                    }
                                    if (ok) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Последнее действие отменено',
                                          ),
                                        ),
                                      );
                                      await _safeSyncDelta(
                                        store,
                                        showErrors: false,
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.undo),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'FCM диагностика',
                        icon: const Icon(Icons.bug_report_outlined),
                        onPressed: _showFcmDiagnosticsDialog,
                      ),
                      IconButton(
                        tooltip: 'Календарь',
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            store.setSelectedDate(picked);
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Синхронизировать',
                        icon: const Icon(Icons.sync),
                        onPressed: () async =>
                            _safeSyncFull(store, showErrors: true),
                      ),
                    ],
                  ),
                  body: loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable: store.pageIndex,
                                builder: (context, page, ____) {
                                  if (page == 0) {
                                    return ValueListenableBuilder<DashboardVm>(
                                      valueListenable: store.dashboard,
                                      builder: (context, vm, _) {
                                        return DashboardView(
                                          vm: vm,
                                          labelFor: _profileLabel,
                                          onOpenCalendar: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: selectedDate,
                                              firstDate: DateTime(2024),
                                              lastDate: DateTime(2035),
                                            );
                                            if (picked != null) {
                                              store.setSelectedDate(picked);
                                            }
                                          },
                                        );
                                      },
                                    );
                                  }
                                  if (page == 1) {
                                    return ValueListenableBuilder<
                                        Map<String, List<TaskItem>>>(
                                      valueListenable: store.personalByStatus,
                                      builder: (context, byStatus, _) {
                                        return TasksBoard(
                                          byStatus: byStatus,
                                          labelFor: _profileLabel,
                                          selectionMode: false,
                                          selectedIds: const <String>{},
                                          onToggleSelect: (_) {},
                                          onDrop: (item, status) async {
                                            await store.move(
                                              item,
                                              status,
                                            );
                                            await _safeSyncDelta(
                                              store,
                                              showErrors: true,
                                            );
                                          },
                                          onEdit: (task) => _openTaskEditor(
                                            store,
                                            existing: task,
                                          ),
                                          onDelete: (task) async {
                                            await store.delete(
                                              task,
                                            );
                                            await _safeSyncDelta(
                                              store,
                                              showErrors: true,
                                            );
                                          },
                                          onDoneToggle: (task) async {
                                            await store.toggleDone(
                                              task,
                                            );
                                            await _safeSyncDelta(
                                              store,
                                              showErrors: true,
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
                                  if (page == 2) {
                                    return ValueListenableBuilder<
                                        List<TaskItem>>(
                                      valueListenable:
                                          store.tasksForSelectedDate,
                                      builder: (context, tasks, _) {
                                        return CalendarView(
                                          selectedDate: selectedDate,
                                          tasksForSelectedDate: tasks,
                                          labelFor: _profileLabel,
                                          onDateChange: store.setSelectedDate,
                                          onEdit: (task) => _openTaskEditor(
                                            store,
                                            existing: task,
                                          ),
                                          onDelete: (task) async {
                                            await store.delete(task);
                                            await _safeSyncDelta(
                                              store,
                                              showErrors: true,
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
                                  if (page == 3) {
                                    return ValueListenableBuilder<String>(
                                      valueListenable: store.familyFilter,
                                      builder: (context, familyFilter, _) {
                                        return ValueListenableBuilder<
                                            List<TaskItem>>(
                                          valueListenable:
                                              store.familyTasksView,
                                          builder: (context, tasks, __) {
                                            return FamilyView(
                                              familyTasks: tasks,
                                              familyFilter: familyFilter,
                                              labelFor: _profileLabel,
                                              onFilterChanged:
                                                  store.setFamilyFilter,
                                              onEdit: (task) => _openTaskEditor(
                                                store,
                                                existing: task,
                                              ),
                                              onDelete: (task) async {
                                                await store.delete(task);
                                                await _safeSyncDelta(
                                                  store,
                                                  showErrors: true,
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  }
                                  return _buildMessengerPage(store,
                                      compact: true);
                                },
                              ),
                            ),
                          ],
                        ),
                  floatingActionButton: ValueListenableBuilder<int>(
                    valueListenable: store.pageIndex,
                    builder: (context, page, _) {
                      if (page != 1 && page != 3) {
                        return const SizedBox.shrink();
                      }
                      return FloatingActionButton.extended(
                        onPressed: () =>
                            _openTaskEditor(store, forceFamily: page == 3),
                        icon: const Icon(Icons.add),
                        label: Text(page == 3 ? 'Семейная задача' : 'Задача'),
                      );
                    },
                  ),
                  bottomNavigationBar: ValueListenableBuilder<int>(
                    valueListenable: store.pageIndex,
                    builder: (context, page, _) {
                      return NavigationBar(
                        selectedIndex: page,
                        onDestinationSelected: (index) {
                          store.setPage(index);
                        },
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.dashboard_outlined),
                            label: 'Сводка',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.view_kanban_outlined),
                            label: 'Задачи',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.calendar_month_outlined),
                            label: 'Календарь',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.family_restroom_outlined),
                            label: 'Семья',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.forum_outlined),
                            label: 'Мессенджер',
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _chatRealtime?.stop();
    _callService?.dispose();
    _chatInputCtl.dispose();
    _fcm?.dispose();
    _cancelSyncLoops();
    unawaited(_desktopProcessHostService?.stopAll());
    _desktopThemeService?.state.dispose();
    _store?.dispose();
    _fcmDiagnostics.dispose();
    super.dispose();
  }
}
