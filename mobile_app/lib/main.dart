import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/task_draft.dart';
import 'domain/task_domain_service.dart';
import 'models/chat_models.dart';
import 'models/task_item.dart';
import 'services/desktop_process_host_service.dart';
import 'services/desktop_theme_service.dart';
import 'repositories/task_repository.dart';
import 'services/api_client.dart';
import 'services/chat_realtime_service.dart';
import 'services/fcm_service.dart';
import 'services/local_db.dart';
import 'state/task_store.dart';

const kProfileLabels = {
  'nik': 'Ник',
  'nastya': 'Настя',
  'misha': 'Миша',
  'arisha': 'Ариша',
  'family': 'Семья',
};

const kWorkflowLabels = {
  'todo': 'К выполнению',
  'in_progress': 'В работе',
  'in_review': 'На проверке',
  'done': 'Выполнено',
};

String profileLabel(String key) => kProfileLabels[key] ?? key;
String workflowLabel(String key) => kWorkflowLabels[key] ?? key;

const _monthNamesRu = [
  'Январь',
  'Февраль',
  'Март',
  'Апрель',
  'Май',
  'Июнь',
  'Июль',
  'Август',
  'Сентябрь',
  'Октябрь',
  'Ноябрь',
  'Декабрь',
];
const _weekDayNamesRu = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _reminderOptions = <int, String>{
  1440: 'За 24 часа',
  720: 'За 12 часов',
  180: 'За 3 часа',
  120: 'За 2 часа',
  60: 'За 1 час',
  30: 'За 30 минут',
  15: 'За 15 минут',
  5: 'За 5 минут',
};

void main() {
  runApp(const FamilyTodoApp());
}

class FamilyTodoApp extends StatelessWidget {
  const FamilyTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Семейные задачи',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF118AB2)),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _profiles = ['nik', 'nastya', 'misha', 'arisha'];

  TaskStore? _store;
  FcmService? _fcm;
  DesktopThemeService? _desktopThemeService;
  DesktopProcessHostService? _desktopProcessHostService;
  Timer? _deltaSyncTimer;
  Timer? _fullSyncTimer;
  bool _desktopLogExpanded = false;
  DateTime _desktopMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _fcmDiagnostics = 'FCM: not initialized';
  final TextEditingController _chatInputCtl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  ChatRealtimeService? _chatRealtime;
  bool _chatLoading = false;
  List<Map<String, String>> _chatContacts = const <Map<String, String>>[];
  List<ChatConversation> _chatConversations = const <ChatConversation>[];
  List<StickerPack> _chatStickerPacks = const <StickerPack>[];
  final Map<String, List<ChatMessage>> _chatMessagesByConversation =
      <String, List<ChatMessage>>{};
  String _activeConversationKey = 'group:common';

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
    final owner =
        savedOwner.isNotEmpty ? savedOwner : await _promptForInitialProfile();
    if (!mounted || owner == null || owner.isEmpty) {
      return;
    }

    final db = await LocalDb.open();
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
    await _initChat(store);
    _startSyncLoops(store);
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() => _store = store);
  }

  Future<String?> _promptForInitialProfile() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return null;
    }
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Выберите профиль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Пуши и синхронизация будут привязаны к выбранному профилю.',
              ),
              const SizedBox(height: 12),
              ..._profiles.map(
                (profile) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(profile);
                    },
                    child: Text(profileLabel(profile)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected.isEmpty) {
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('actor_profile', selected);
    return selected;
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
                        DropdownButton<String>(
                          value: owner,
                          onChanged: (value) async {
                            if (value != null) {
                              await _switchProfile(store, value);
                            }
                          },
                          items: _profiles
                              .map(
                                (profile) => DropdownMenuItem<String>(
                                  value: profile,
                                  child: Text(profileLabel(profile)),
                                ),
                              )
                              .toList(),
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
              return _DashboardView(
                vm: vm,
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
              final selectedDateKey = _dateKey(selectedDate);
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
                    child: _DesktopTasksBoard(
                      byStatus: byStatus,
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
              return _DesktopCalendarView(
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
                  return _FamilyView(
                    familyTasks: tasks,
                    familyFilter: familyFilter,
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
      setState(() {
        _fcmDiagnostics = 'FCM: binding actor=$owner';
      });
    }
    _fcm = FcmService(
      api: api,
      actorProfile: owner,
      onForegroundText: (text) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      },
      onDiagnosticsChanged: (text) {
        debugPrint('FCM diagnostics: $text');
        if (!mounted) {
          return;
        }
        setState(() {
          _fcmDiagnostics = text;
        });
      },
      onOpenPush: () async {
        final store = _store;
        if (store == null) {
          return;
        }
        await _safeSyncDelta(store, showErrors: false);
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
        return AlertDialog(
          title: const Text('FCM диагностика'),
          content: SingleChildScrollView(
            child: SelectableText(_fcmDiagnostics),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFcmDiagnosticsCard() {
    final lines = _fcmDiagnostics.split('\n');
    final preview =
        lines.length <= 4 ? _fcmDiagnostics : lines.take(4).join('\n');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: const Color(0xFFFFF7E6),
      child: ListTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('FCM диагностика'),
        subtitle: Text(preview),
        trailing: TextButton(
          onPressed: _showFcmDiagnosticsDialog,
          child: const Text('Подробно'),
        ),
      ),
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
  }

  void _cancelSyncLoops() {
    _deltaSyncTimer?.cancel();
    _deltaSyncTimer = null;
    _fullSyncTimer?.cancel();
    _fullSyncTimer = null;
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

  Future<void> _switchProfile(TaskStore store, String profile) async {
    if (profile == store.owner.value) {
      return;
    }
    _cancelSyncLoops();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('actor_profile', profile);
    await store.switchOwner(profile);
    await _desktopThemeService?.switchProfile(profile);
    _bindFcm(api: store.repository.api, owner: profile);
    await _initChat(store);
    _startSyncLoops(store);
  }

  Future<void> _initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    setState(() {
      _chatLoading = true;
      _chatMessagesByConversation.clear();
      _activeConversationKey = 'group:common';
    });

    try {
      final bootstrap = await api.chatBootstrap(actorProfile: actor);
      for (final conversation in bootstrap.conversations) {
        await db.upsertConversation(conversation);
      }
      await db.replaceStickerPacks(bootstrap.stickerPacks);

      final conversations = await db.readConversations();
      final stickerPacks = await db.readStickerPacks();

      var active = bootstrap.groupConversationKey;
      if (active.isEmpty) {
        active = conversations.isEmpty
            ? 'group:common'
            : conversations.first.conversationKey;
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _chatContacts = bootstrap.contacts;
        _chatConversations = conversations;
        _chatStickerPacks = stickerPacks;
        _activeConversationKey = active;
      });

      await _refreshActiveConversation(store, useNetwork: true, quiet: true);
      await _chatRealtime?.stop();
      _chatRealtime = ChatRealtimeService(
        api: api,
        actorProfile: actor,
        activeConversationKey: () => _activeConversationKey,
        shouldPoll: () => mounted && _store?.pageIndex.value == 4,
        onMessagesUpdated: (conversationKey) async {
          await _refreshConversation(
            store,
            conversationKey,
            useNetwork: true,
            quiet: true,
          );
        },
      )..start();
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

  Future<void> _refreshActiveConversation(
    TaskStore store, {
    required bool useNetwork,
    required bool quiet,
  }) async {
    if (_activeConversationKey.isEmpty) {
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
    final db = store.repository.db;
    final api = store.repository.api;
    final actor = store.owner.value;
    final previous =
        _chatMessagesByConversation[conversationKey] ?? const <ChatMessage>[];

    try {
      final local = await db.readMessages(conversationKey: conversationKey);
      if (mounted && !_sameMessages(previous, local)) {
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
      await db.upsertMessages(snapshot.messages);
      if (snapshot.nextCursor != null && snapshot.nextCursor!.isNotEmpty) {
        await db.saveChatCursor(
          conversationKey: conversationKey,
          cursor: snapshot.nextCursor!,
        );
      }

      final merged = await db.readMessages(conversationKey: conversationKey);
      final beforeMerged =
          _chatMessagesByConversation[conversationKey] ?? const <ChatMessage>[];
      if (mounted && !_sameMessages(beforeMerged, merged)) {
        setState(() {
          _chatMessagesByConversation[conversationKey] = merged;
        });
      }
    } catch (error) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления чата: $error')),
        );
      }
    }
  }

  Future<void> _openConversation(
      TaskStore store, String conversationKey) async {
    if (!mounted) {
      return;
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

  Future<void> _sendTextMessage(TaskStore store) async {
    final text = _chatInputCtl.text.trim();
    if (text.isEmpty) {
      return;
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    try {
      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: 'text',
        text: text,
        clientMessageId: 'mobile-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.upsertMessages([message]);
      _chatInputCtl.clear();
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
        SnackBar(content: Text('Ошибка отправки: $error')),
      );
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

  Future<void> _sendImageSticker(TaskStore store) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (picked == null) {
      return;
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;

    try {
      final bytes = await picked.readAsBytes();
      final uploaded = await api.chatUploadSticker(
        actorProfile: actor,
        bytes: bytes,
        filename: picked.name,
      );
      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: 'image',
        imageUrl: uploaded.assetUrl,
        imageMeta: uploaded.imageMeta,
        clientMessageId: 'img-${DateTime.now().microsecondsSinceEpoch}',
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
        SnackBar(content: Text('Ошибка отправки изображения: $error')),
      );
    }
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
                        await _sendImageSticker(store);
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
                                child: Text(item.title),
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

  Widget _buildMessengerPage(TaskStore store, {required bool compact}) {
    final conversations = _chatConversations;
    final messages = _chatMessagesByConversation[_activeConversationKey] ??
        const <ChatMessage>[];

    if (_chatLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final conversation in conversations)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                        _conversationLabel(conversation, store.owner.value)),
                    selected:
                        _activeConversationKey == conversation.conversationKey,
                    onSelected: (_) =>
                        _openConversation(store, conversation.conversationKey),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final mine = message.senderProfile == store.owner.value;
              final text = _chatMessageText(message);
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: compact ? 320 : 560,
                  ),
                  decoration: BoxDecoration(
                    color: mine
                        ? const Color(0xFFDDF4FF)
                        : const Color(0xFFF2F4F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        profileLabel(message.senderProfile),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (message.messageType == 'image' &&
                          (message.imageUrl ?? '').isNotEmpty)
                        SelectableText(
                          message.imageUrl!,
                          style: const TextStyle(
                            decoration: TextDecoration.underline,
                          ),
                        )
                      else
                        Text(text),
                      const SizedBox(height: 4),
                      Text(
                        message.createdAt,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Стикеры',
                icon: const Icon(Icons.emoji_emotions_outlined),
                onPressed: () => _openStickerSheet(store),
              ),
              Expanded(
                child: TextField(
                  controller: _chatInputCtl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Введите сообщение',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _sendTextMessage(store),
                icon: const Icon(Icons.send),
                label: const Text('Отправить'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _conversationLabel(ChatConversation conversation, String actor) {
    if (conversation.kind == 'group' ||
        conversation.conversationKey == 'group:common') {
      return 'Общий';
    }
    final peer = conversation.members.firstWhere(
      (item) => item != actor,
      orElse: () => '',
    );
    if (peer.isNotEmpty) {
      return profileLabel(peer);
    }

    final fromContacts = _chatContacts.firstWhere(
      (item) => item['conversation_key'] == conversation.conversationKey,
      orElse: () => const {'profile_key': ''},
    )['profile_key'];
    if ((fromContacts ?? '').isNotEmpty) {
      return profileLabel(fromContacts!);
    }
    return conversation.conversationKey;
  }

  String _chatMessageText(ChatMessage message) {
    if (message.messageType == 'sticker') {
      final id = message.stickerId ?? '';
      if (id.isEmpty) {
        return 'Стикер';
      }
      for (final pack in _chatStickerPacks) {
        for (final item in pack.items) {
          if (item.stickerId == id) {
            return 'Стикер: ${item.title}';
          }
        }
      }
      return 'Стикер';
    }
    if (message.messageType == 'image') {
      return 'Изображение';
    }
    return message.text;
  }

  bool _sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
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
          left.stickerId != right.stickerId) {
        return false;
      }
    }
    return true;
  }

  String _dateKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> _openTaskEditor(
    TaskStore store, {
    TaskItem? existing,
    bool forceFamily = false,
  }) async {
    final titleCtl = TextEditingController(text: existing?.title ?? '');
    final detailsCtl = TextEditingController(text: existing?.details ?? '');
    final durationCtl = TextEditingController(
      text: existing == null ? '' : existing.durationMinutes.toString(),
    );
    final selectedAssignees = <String>{
      ...(existing?.assignees ?? const <String>[]),
    };
    DateTime selected = existing == null
        ? store.selectedDate.value
        : DateTime.tryParse(existing.dueDate) ?? store.selectedDate.value;
    String time = existing?.time ?? '19:00';
    String priority = existing?.priority ?? 'medium';
    String status = existing?.workflowStatus ?? 'todo';
    bool isFamily = forceFamily || (existing?.isFamily ?? false);
    final selectedReminderOffsets = <int>{
      ...(existing?.reminderOffsetsMinutes ?? const <int>[]),
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? 'Новая задача'
                          : 'Редактирование задачи',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtl,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    TextField(
                      controller: detailsCtl,
                      decoration: const InputDecoration(labelText: 'Описание'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_month),
                            label: Text(_dateKey(selected)),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selected,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                setModalState(() => selected = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.schedule),
                            label: Text(time),
                            onPressed: () async {
                              final parts = time.split(':');
                              final initial = TimeOfDay(
                                hour: int.tryParse(parts.first) ?? 19,
                                minute: int.tryParse(
                                      parts.length > 1 ? parts[1] : '0',
                                    ) ??
                                    0,
                              );
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: initial,
                              );
                              if (picked != null) {
                                setModalState(() {
                                  time =
                                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: 'Приоритет'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Низкий')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('Средний'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('Высокий')),
                      ],
                      onChanged: (value) =>
                          setModalState(() => priority = value ?? 'medium'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Статус'),
                      items: const [
                        DropdownMenuItem(
                          value: 'todo',
                          child: Text('К выполнению'),
                        ),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('В работе'),
                        ),
                        DropdownMenuItem(
                          value: 'in_review',
                          child: Text('На проверке'),
                        ),
                        DropdownMenuItem(
                          value: 'done',
                          child: Text('Выполнено'),
                        ),
                      ],
                      onChanged: (value) =>
                          setModalState(() => status = value ?? 'todo'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Семейная задача'),
                      value: isFamily,
                      onChanged: forceFamily
                          ? null
                          : (value) => setModalState(() => isFamily = value),
                    ),
                    if (isFamily) ...[
                      TextField(
                        controller: durationCtl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Длительность (мин)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ответственные',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _profiles.map((profile) {
                          return FilterChip(
                            label: Text(profileLabel(profile)),
                            selected: selectedAssignees.contains(profile),
                            onSelected: (selected) {
                              setModalState(() {
                                if (selected) {
                                  selectedAssignees.add(profile);
                                } else {
                                  selectedAssignees.remove(profile);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Напоминания',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reminderOptions.entries.map((entry) {
                        final offset = entry.key;
                        return FilterChip(
                          label: Text(entry.value),
                          selected: selectedReminderOffsets.contains(offset),
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                selectedReminderOffsets.add(offset);
                              } else {
                                selectedReminderOffsets.remove(offset);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final draft = TaskDraft(
                                title: titleCtl.text.trim(),
                                details: detailsCtl.text.trim(),
                                dueDate: _dateKey(selected),
                                time: time,
                                priority: priority,
                                workflowStatus: status,
                                isFamily: isFamily,
                                assignees: selectedAssignees.toList(),
                                durationMinutes:
                                    int.tryParse(durationCtl.text.trim()) ?? 0,
                                reminderOffsetsMinutes:
                                    selectedReminderOffsets.toList(),
                              );
                              final messenger =
                                  ScaffoldMessenger.of(this.context);
                              final error = await store.saveDraft(
                                draft: draft,
                                existing: existing,
                              );
                              if (error != null && mounted) {
                                messenger.showSnackBar(
                                    SnackBar(content: Text(error)));
                                return;
                              }
                              if (!mounted) {
                                return;
                              }
                              Navigator.of(this.context).pop();
                              await _safeSyncDelta(store, showErrors: true);
                            },
                            child: const Text('Сохранить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
    await store.moveToDate(item, _dateKey(target));
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
                final selectedDateKey = _dateKey(selectedDate);
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
                    title: Text('Семейные задачи - $selectedDateKey'),
                    actions: [
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
                      PopupMenuButton<String>(
                        initialValue: owner,
                        onSelected: (value) async =>
                            _switchProfile(store, value),
                        itemBuilder: (context) => _profiles
                            .map(
                              (profile) => PopupMenuItem<String>(
                                value: profile,
                                child: Text(profileLabel(profile)),
                              ),
                            )
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Center(
                            child: Text(
                              profileLabel(owner),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
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
                            _buildFcmDiagnosticsCard(),
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable: store.pageIndex,
                                builder: (context, page, ____) {
                                  if (page == 0) {
                                    return ValueListenableBuilder<DashboardVm>(
                                      valueListenable: store.dashboard,
                                      builder: (context, vm, _) {
                                        return _DashboardView(
                                          vm: vm,
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
                                        return _TasksBoard(
                                          byStatus: byStatus,
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
                                        return _CalendarView(
                                          selectedDate: selectedDate,
                                          tasksForSelectedDate: tasks,
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
                                            return _FamilyView(
                                              familyTasks: tasks,
                                              familyFilter: familyFilter,
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
                        onDestinationSelected: store.setPage,
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
    _chatInputCtl.dispose();
    _fcm?.dispose();
    _cancelSyncLoops();
    unawaited(_desktopProcessHostService?.stopAll());
    _desktopThemeService?.state.dispose();
    _store?.dispose();
    super.dispose();
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.vm, required this.onOpenCalendar});

  final DashboardVm vm;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'На дату',
                value: '${vm.todayTotal}',
                hint: vm.todayKey,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Сделано',
                value: '${vm.doneToday}',
                hint: 'Выполнено',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Семейных',
                value: '${vm.familyToday}',
                hint: 'Семейные',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Просрочено',
                value: '${vm.overdue}',
                hint: 'Просрочка',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onOpenCalendar,
          icon: const Icon(Icons.calendar_month),
          label: const Text('Выбрать дату'),
        ),
        const SizedBox(height: 12),
        Text('Ближайшие задачи', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final task in vm.upcoming)
          Card(
            child: ListTile(
              title: Text(task.title),
              subtitle: Text(
                '${task.dueDate} ${task.time} - ${profileLabel(task.ownerKey)} - ${workflowLabel(task.workflowStatus)}',
              ),
              trailing:
                  task.isFamily ? const Icon(Icons.family_restroom) : null,
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.hint,
  });

  final String title;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.selectedDate,
    required this.tasksForSelectedDate,
    required this.onDateChange,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime selectedDate;
  final List<TaskItem> tasksForSelectedDate;
  final void Function(DateTime) onDateChange;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    final start = selectedDate.subtract(const Duration(days: 3));
    final days = List.generate(10, (index) => start.add(Duration(days: index)));

    return Column(
      children: [
        SizedBox(
          height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final date = days[index];
              final isCurrent = date.year == selectedDate.year &&
                  date.month == selectedDate.month &&
                  date.day == selectedDate.day;
              return ChoiceChip(
                selected: isCurrent,
                label: Text(
                  '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}',
                ),
                onSelected: (_) => onDateChange(date),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if (tasksForSelectedDate.isEmpty)
                const Card(
                  child: ListTile(title: Text('На выбранную дату задач нет')),
                ),
              for (final item in tasksForSelectedDate)
                _TaskCard(
                  item: item,
                  onEdit: () => onEdit(item),
                  onDelete: () => onDelete(item),
                  onDoneToggle: () async {},
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TasksBoard extends StatelessWidget {
  const _TasksBoard({
    required this.byStatus,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
  final Future<void> Function(TaskItem, String) onDrop;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;

  static const _titles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
  };

  static const _colors = {
    'todo': Color(0xFFE3F2FD),
    'in_progress': Color(0xFFE8F5E9),
    'in_review': Color(0xFFFFF3E0),
    'done': Color(0xFFEDE7F6),
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: _titles.keys.map((status) {
        final items = byStatus[status] ?? const <TaskItem>[];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: _colors[status],
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DragTarget<TaskItem>(
              onAcceptWithDetails: (details) => onDrop(details.data, status),
              builder: (context, candidate, rejected) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_titles[status]} (${items.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final item in items)
                      LongPressDraggable<TaskItem>(
                        data: item,
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 260,
                            child: _TaskCard(
                              item: item,
                              onEdit: () async {},
                              onDelete: () async {},
                              onDoneToggle: () async {},
                            ),
                          ),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: _TaskCard(
                          item: item,
                          selectionMode: selectionMode,
                          selected: selectedIds.contains(item.id),
                          onSelectionToggle: () => onToggleSelect(item.id),
                          onEdit: () => onEdit(item),
                          onDelete: () => onDelete(item),
                          onDoneToggle: () => onDoneToggle(item),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DesktopTasksBoard extends StatelessWidget {
  const _DesktopTasksBoard({
    required this.byStatus,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDropStatus,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String) onToggleSelect;
  final Future<void> Function(TaskItem, String) onDropStatus;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(TaskItem) onDoneToggle;

  static const _titles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: 4 * 340,
            height: constraints.maxHeight,
            child: Row(
              children: _titles.keys.map((status) {
                final items = byStatus[status] ?? const <TaskItem>[];
                return SizedBox(
                  width: 330,
                  child: Card(
                    margin: const EdgeInsets.only(right: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_titles[status]} (${items.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DragTarget<TaskItem>(
                              onAcceptWithDetails: (details) =>
                                  onDropStatus(details.data, status),
                              builder: (context, _, __) {
                                return ListView(
                                  children: [
                                    for (final item in items)
                                      LongPressDraggable<TaskItem>(
                                        data: item,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width: 280,
                                            child: _TaskCard(
                                              item: item,
                                              onEdit: () async {},
                                              onDelete: () async {},
                                              onDoneToggle: () async {},
                                            ),
                                          ),
                                        ),
                                        childWhenDragging:
                                            const SizedBox.shrink(),
                                        child: _TaskCard(
                                          item: item,
                                          selectionMode: selectionMode,
                                          selected:
                                              selectedIds.contains(item.id),
                                          onSelectionToggle: () =>
                                              onToggleSelect(item.id),
                                          onEdit: () => onEdit(item),
                                          onDelete: () => onDelete(item),
                                          onDoneToggle: () =>
                                              onDoneToggle(item),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopCalendarView extends StatelessWidget {
  const _DesktopCalendarView({
    required this.month,
    required this.selectedDate,
    required this.allTasks,
    required this.monthGrid,
    required this.onGoPrevMonth,
    required this.onGoNextMonth,
    required this.onGoToday,
    required this.onSelectDate,
    required this.onDropToDay,
    required this.onDropToStatus,
    required this.onOpenEditor,
    required this.onDelete,
    required this.onAddForDate,
  });

  final DateTime month;
  final DateTime selectedDate;
  final List<TaskItem> allTasks;
  final List<DateTime> monthGrid;
  final VoidCallback onGoPrevMonth;
  final VoidCallback onGoNextMonth;
  final VoidCallback onGoToday;
  final void Function(DateTime) onSelectDate;
  final Future<void> Function(TaskItem, DateTime) onDropToDay;
  final Future<void> Function(TaskItem, String) onDropToStatus;
  final Future<void> Function(DateTime, TaskItem) onOpenEditor;
  final Future<void> Function(TaskItem) onDelete;
  final Future<void> Function(DateTime) onAddForDate;

  static const _statusTitles = {
    'todo': 'К выполнению',
    'in_progress': 'В работе',
    'in_review': 'На проверке',
    'done': 'Выполнено',
  };

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<TaskItem>>{};
    for (final task in allTasks) {
      byDate.putIfAbsent(task.dueDate, () => <TaskItem>[]).add(task);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onGoPrevMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_monthNamesRu[month.month - 1]} ${month.year}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                onPressed: onGoNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: onGoToday, child: const Text('Сегодня')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in _weekDayNamesRu)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.14,
              ),
              itemCount: monthGrid.length,
              itemBuilder: (context, index) {
                final day = monthGrid[index];
                final key =
                    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                final dayTasks = byDate[key] ?? const <TaskItem>[];
                final isCurrentMonth = day.month == month.month;
                final isSelected = day.year == selectedDate.year &&
                    day.month == selectedDate.month &&
                    day.day == selectedDate.day;
                final visible = dayTasks.take(3).toList();
                final overflow = dayTasks.length - visible.length;
                return DragTarget<TaskItem>(
                  onAcceptWithDetails: (details) =>
                      onDropToDay(details.data, day),
                  builder: (context, _, __) {
                    return InkWell(
                      onTap: () => onSelectDate(day),
                      onDoubleTap: () async {
                        await _openDayPopup(context, day, dayTasks);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFEAF2FF)
                              : const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrentMonth
                                ? const Color(0xFFD9E2EF)
                                : const Color(0xFFEDEFF3),
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                color: isCurrentMonth
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF9CA3AF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final item in visible)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: LongPressDraggable<TaskItem>(
                                  data: item,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: Chip(label: Text(item.title)),
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDBEAFE),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ),
                            if (overflow > 0)
                              TextButton(
                                onPressed: () =>
                                    _openDayPopup(context, day, dayTasks),
                                child: Text('+$overflow еще'),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: Row(
              children: _statusTitles.keys.map((status) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: DragTarget<TaskItem>(
                      onAcceptWithDetails: (details) =>
                          onDropToStatus(details.data, status),
                      builder: (context, _, __) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFD9E2EF)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(_statusTitles[status]!),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDayPopup(
    BuildContext context,
    DateTime day,
    List<TaskItem> dayTasks,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}',
          ),
          content: SizedBox(
            width: 520,
            child: dayTasks.isEmpty
                ? const Text('На эту дату задач нет')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final task in dayTasks)
                        ListTile(
                          dense: true,
                          title: Text(task.title),
                          subtitle: Text(
                            '${task.time} · ${workflowLabel(task.workflowStatus)}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: () => onOpenEditor(day, task),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                onPressed: () => onDelete(task),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await onAddForDate(day);
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }
}

class _FamilyView extends StatelessWidget {
  const _FamilyView({
    required this.familyTasks,
    required this.familyFilter,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TaskItem> familyTasks;
  final String familyFilter;
  final void Function(String) onFilterChanged;
  final Future<void> Function(TaskItem) onEdit;
  final Future<void> Function(TaskItem) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'upcoming', label: Text('Предстоящие')),
              ButtonSegment(value: 'overdue', label: Text('Просроченные')),
              ButtonSegment(value: 'done', label: Text('Выполненные')),
              ButtonSegment(value: 'all', label: Text('Все')),
            ],
            selected: <String>{familyFilter},
            onSelectionChanged: (values) => onFilterChanged(values.first),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'Семейные задачи',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (familyTasks.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Под выбранный фильтр задач нет'),
                  ),
                ),
              for (final item in familyTasks)
                _TaskCard(
                  item: item,
                  onEdit: () => onEdit(item),
                  onDelete: () => onDelete(item),
                  onDoneToggle: () async {},
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  final TaskItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionToggle;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onDoneToggle;

  @override
  Widget build(BuildContext context) {
    final assigneeLabels = item.assignees.map(profileLabel).toList();
    final subtitle = [
      '${item.dueDate} ${item.time}'.trim(),
      'Статус: ${workflowLabel(item.workflowStatus)}',
      if (item.isFamily && assigneeLabels.isNotEmpty)
        'Ответственные: ${assigneeLabels.join(', ')}',
      if (item.isFamily && item.durationMinutes > 0)
        'Длительность: ${item.durationMinutes} мин',
      if (item.details.isNotEmpty) item.details,
      'Владелец: ${profileLabel(item.ownerKey)}',
    ].join('\n');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: selectionMode ? onSelectionToggle : () => onEdit(),
        leading: selectionMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => onSelectionToggle?.call(),
              )
            : null,
        title: Text(item.title),
        subtitle: Text(subtitle),
        isThreeLine: true,
        trailing: selectionMode
            ? null
            : Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Выполнить/отменить',
                    icon: Icon(
                      item.workflowStatus == 'done'
                          ? Icons.undo
                          : Icons.check_circle,
                    ),
                    onPressed: () => onDoneToggle(),
                  ),
                  IconButton(
                    tooltip: 'Удалить',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onDelete(),
                  ),
                ],
              ),
      ),
    );
  }
}
