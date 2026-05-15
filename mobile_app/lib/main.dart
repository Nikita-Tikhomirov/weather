import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'domain/task_draft.dart';
import 'domain/task_domain_service.dart';
import 'models/chat_models.dart';
import 'models/project_contact.dart';
import 'models/task_item.dart';
import 'services/desktop_process_host_service.dart';
import 'services/desktop_theme_service.dart';
import 'services/project_bridge_service.dart';
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

class AppThemeOption {
  const AppThemeOption({
    required this.key,
    required this.name,
    required this.seed,
    required this.scaffold,
    this.brightness = Brightness.light,
  });

  final String key;
  final String name;
  final Color seed;
  final Color scaffold;
  final Brightness brightness;
}

const _appThemeOptions = <AppThemeOption>[
  AppThemeOption(
    key: 'ocean',
    name: 'Океан',
    seed: Color(0xFF118AB2),
    scaffold: Color(0xFFF7FAFC),
  ),
  AppThemeOption(
    key: 'mint',
    name: 'Мята',
    seed: Color(0xFF2A9D8F),
    scaffold: Color(0xFFF3FBF8),
  ),
  AppThemeOption(
    key: 'coral',
    name: 'Коралл',
    seed: Color(0xFFE76F51),
    scaffold: Color(0xFFFFF7F4),
  ),
  AppThemeOption(
    key: 'iris',
    name: 'Ирис',
    seed: Color(0xFF6D5BD0),
    scaffold: Color(0xFFF8F7FF),
  ),
  AppThemeOption(
    key: 'forest',
    name: 'Лес',
    seed: Color(0xFF2D6A4F),
    scaffold: Color(0xFFF5FAF6),
  ),
  AppThemeOption(
    key: 'sky_dark',
    name: 'Ночь',
    seed: Color(0xFF60A5FA),
    scaffold: Color(0xFF0F172A),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'graphite',
    name: 'Графит',
    seed: Color(0xFF94A3B8),
    scaffold: Color(0xFF111827),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'plum',
    name: 'Слива',
    seed: Color(0xFFC084FC),
    scaffold: Color(0xFF1E1B2E),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'pine',
    name: 'Хвоя',
    seed: Color(0xFF34D399),
    scaffold: Color(0xFF10201A),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    key: 'amber',
    name: 'Янтарь',
    seed: Color(0xFFF59E0B),
    scaffold: Color(0xFF211A10),
    brightness: Brightness.dark,
  ),
];

AppThemeOption _themeOptionByKey(String key) {
  return _appThemeOptions.firstWhere(
    (option) => option.key == key,
    orElse: () => _appThemeOptions.first,
  );
}

ThemeData _buildAppTheme(AppThemeOption option) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: option.seed,
    brightness: option.brightness,
  );
  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: option.scaffold,
    useMaterial3: true,
  );
}

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

class FamilyTodoApp extends StatefulWidget {
  const FamilyTodoApp({super.key});

  @override
  State<FamilyTodoApp> createState() => _FamilyTodoAppState();
}

class _FamilyTodoAppState extends State<FamilyTodoApp> {
  String _themeKey = _appThemeOptions.first.key;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_theme_key') ?? _themeKey;
    if (!mounted) {
      return;
    }
    setState(() => _themeKey = _themeOptionByKey(saved).key);
  }

  Future<void> _setTheme(String key) async {
    final normalized = _themeOptionByKey(key).key;
    setState(() => _themeKey = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_key', normalized);
  }

  @override
  Widget build(BuildContext context) {
    final option = _themeOptionByKey(_themeKey);
    return MaterialApp(
      title: 'Семейные задачи',
      debugShowCheckedModeBanner: false,
      theme: _buildAppTheme(option),
      home: HomePage(
        selectedThemeKey: option.key,
        onThemeChanged: _setTheme,
      ),
    );
  }
}

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
  bool _desktopLogExpanded = false;
  DateTime _desktopMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _fcmDiagnostics = 'FCM: not initialized';
  final TextEditingController _chatInputCtl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  ChatRealtimeService? _chatRealtime;
  bool _chatLoading = false;
  String? _editingMessageId;
  List<ChatContact> _chatContacts = const <ChatContact>[];
  List<ChatContact> _phoneContacts = const <ChatContact>[];
  List<ChatContact> _familyMembers = const <ChatContact>[];
  List<ProjectContact> _projectContacts = const <ProjectContact>[];
  ProjectBridgeService? _projectBridge;
  final List<BridgeMessage> _projectMessages = <BridgeMessage>[];
  List<ChatConversation> _chatConversations = const <ChatConversation>[];
  List<StickerPack> _chatStickerPacks = const <StickerPack>[];
  final Map<String, List<ChatMessage>> _chatMessagesByConversation =
      <String, List<ChatMessage>>{};
  String _activeConversationKey = '';
  String _currentProfileDisplayName = '';
  ChatMessage? _replyToMessage;
  String? _replyToMessageId;
  bool _isRecording = false;
  String? _voicePath;
  Timer? _voiceTimer;
  int _voiceSec = 0;

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
    _startSyncLoops(store);
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() => _store = store);
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
    /*
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
    */
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
              return _DashboardView(
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
      onOpenPush: (data) async {
        final store = _store;
        if (store == null) {
          return;
        }
        await _safeSyncDelta(store, showErrors: false);
        store.setPage(4); // Switch to Messenger tab
        final conversationKey = (data['conversation_key'] ?? '').trim();
        if ((data['entity'] ?? '') == 'chat_message' &&
            conversationKey.isNotEmpty &&
            !_isProjectConversation(conversationKey)) {
          await _openConversation(store, conversationKey);
          return;
        }
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
                title: Text(_contactLabel(allContacts[i])),
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
        setState(() => _activeConversationKey = conversationKey);
        await _refreshConversation(store, conversationKey,
            useNetwork: true, quiet: true);
      } catch (_) {
        // silently ignore share errors
      }
    });
  }

  Future<void> _initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    setState(() {
      _chatLoading = true;
      _chatMessagesByConversation.clear();
      _activeConversationKey = '';
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
      setState(() {
        _chatContacts = bootstrap.contacts;
        _chatConversations = conversations;
        _chatStickerPacks = stickerPacks;
        _activeConversationKey = '';
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
            !_isProjectConversation(_activeConversationKey),
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

  void _loadProjects() {
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
      // Ignore errors loading projects config
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
    if (!mounted) {
      return;
    }

    // Set active conversation to project key
    setState(() {
      _activeConversationKey = project.conversationKey;
      _projectMessages.clear();
    });

    // Stop existing bridge if any
    _projectBridge?.dispose();
    _projectBridge = null;

    // Connect to the remote bridge server running on PC
    final bridge = ProjectBridgeService(
      onMessage: (msg) {
        if (mounted) {
          if (msg.isHistory) {
            setState(() {
              _projectMessages
                ..clear()
                ..addAll(msg.messages);
            });
            return;
          }
          if (msg.isProjects && msg.projects.isNotEmpty) {
            setState(() {
              _projectContacts =
                  msg.projects.map((p) => ProjectContact.fromJson(p)).toList();
            });
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

    // Remember the selected project before connecting so reconnects can resume it.
    bridge.startProject(project);
    await ProjectBridgeService.requestBridgeStart(project);
    final ok = await bridge.connect();
    if (!ok) return;
  }

  bool _isProjectConversation(String key) => key.startsWith('project:');

  ProjectContact? _projectByConversationKey(String key) {
    if (!_isProjectConversation(key)) {
      return null;
    }
    return _projectContacts.cast<ProjectContact?>().firstWhere(
          (p) => p?.conversationKey == key,
          orElse: () => null,
        );
  }

  Future<void> _refreshActiveConversation(
    TaskStore store, {
    required bool useNetwork,
    required bool quiet,
  }) async {
    if (_activeConversationKey.isEmpty) {
      return;
    }
    // Skip project conversations (handled by bridge)
    if (_isProjectConversation(_activeConversationKey)) {
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
    conversationKey = _canonicalConversationKey(conversationKey);
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
      final canonicalKey = snapshot.messages.isEmpty
          ? conversationKey
          : _canonicalConversationKey(snapshot.messages.first.conversationKey);
      await db.upsertMessages(snapshot.messages);
      if (snapshot.nextCursor != null && snapshot.nextCursor!.isNotEmpty) {
        await db.saveChatCursor(
          conversationKey: canonicalKey,
          cursor: snapshot.nextCursor!,
        );
      }

      final merged = await db.readMessages(conversationKey: canonicalKey);
      final beforeMerged =
          _chatMessagesByConversation[canonicalKey] ?? const <ChatMessage>[];
      if (mounted && !_sameMessages(beforeMerged, merged)) {
        setState(() {
          _chatMessagesByConversation[canonicalKey] = merged;
          if (_activeConversationKey == conversationKey &&
              canonicalKey != conversationKey) {
            _activeConversationKey = canonicalKey;
          }
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
    conversationKey = _canonicalConversationKey(conversationKey);
    // Clean up project bridge when switching to regular conversation
    if (_isProjectConversation(_activeConversationKey)) {
      _projectBridge?.dispose();
      _projectBridge = null;
      _projectMessages.clear();
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

  String _canonicalConversationKey(String key) {
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
                            title: Text(_contactLabel(contact)),
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
          SnackBar(content: Text('${_contactLabel(contact)} добавлен в семью')),
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

  Future<void> _sendTextMessage(TaskStore store) async {
    // Route to project bridge for project conversations
    if (_isProjectConversation(_activeConversationKey)) {
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
      } else if (replyTo.messageType == 'voice') {
        finalText = '> $senderLabel: [voice] ${replyTo.text}\n$text';
      } else {
        finalText =
            '> $senderLabel: ${replyTo.text.split('\n').join('\n> ')}\n$text';
      }
    }

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;
    try {
      final editingId = _editingMessageId;
      final message = editingId == null
          ? await api.chatSendMessage(
              actorProfile: actor,
              conversationKey: conversationKey,
              messageType: 'text',
              text: finalText,
              clientMessageId:
                  'mobile-${DateTime.now().microsecondsSinceEpoch}',
            )
          : await api.chatEditMessage(
              actorProfile: actor,
              messageId: editingId,
              text: text,
            );
      await db.upsertMessages([message]);
      _chatInputCtl.clear();
      setState(() {
        _editingMessageId = null;
        _replyToMessage = null;
        _replyToMessageId = null;
      });
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
                title: Text(_contactLabel(contact)),
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
      await _refreshConversation(store, conversationKey,
          useNetwork: true, quiet: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Переслано → ${_contactLabel(selected)}')),
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
        _replyToMessageId = message.id;
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

    // Optional photo caption
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

    final actor = store.owner.value;
    final api = store.repository.api;
    final db = store.repository.db;
    final conversationKey = _activeConversationKey;

    try {
      final attachments = <ChatAttachment>[];
      for (var i = 0; i < picked.length; i++) {
        final file = picked[i];
        final bytes = await file.readAsBytes();
        final uploaded = await api.chatUploadSticker(
          actorProfile: actor,
          bytes: bytes,
          filename: file.name,
        );
        attachments.add(ChatAttachment(
          kind: 'image',
          assetUrl: uploaded.assetUrl,
          imageMeta: uploaded.imageMeta,
          sortOrder: i,
        ));
      }
      final message = await api.chatSendMessage(
        actorProfile: actor,
        conversationKey: conversationKey,
        messageType: attachments.length == 1 ? 'image' : 'image_group',
        text: caption,
        imageUrl: null,
        imageMeta: null,
        attachments: attachments,
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
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('Стикер'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openStickerSheet(store);
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

  Widget _buildMessengerPage(TaskStore store, {required bool compact}) {
    final conversations = _chatConversations;
    final messages = _chatMessagesByConversation[_activeConversationKey] ??
        const <ChatMessage>[];

    if (_chatLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeConversationKey.isEmpty) {
      final contacts = _phoneContacts.isEmpty ? _chatContacts : _phoneContacts;
      final projects = _projectContacts;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Контакты',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить контакты',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _loadPhoneContacts(store),
                ),
                IconButton.filled(
                  tooltip: 'Создать группу',
                  icon: const Icon(Icons.group_add_outlined),
                  onPressed: () => _openCreateGroupSheet(store),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                // Regular contacts
                if (contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Нет зарегистрированных контактов из телефона'),
                  )
                else
                  ...List.generate(contacts.length, (index) {
                    final contact = contacts[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(_contactLabel(contact)),
                      subtitle: Text(contact.phone),
                      trailing: IconButton(
                        tooltip: 'Добавить в семью',
                        icon: const Icon(Icons.family_restroom_outlined),
                        onPressed: () => _addContactToFamily(store, contact),
                      ),
                      onTap: () => _openDirectContact(store, contact),
                    );
                  }),
                // Projects section
                if (projects.isNotEmpty) ...[
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Проекты (терминалы)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Настроить сервер',
                          icon: const Icon(Icons.settings, size: 20),
                          onPressed: () => _openBridgeSettings(),
                        ),
                      ],
                    ),
                  ),
                  ...projects.map((project) {
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(_projectIcon(project.icon)),
                      ),
                      title: Text(project.name),
                      subtitle: Text(project.path,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.terminal),
                      onTap: () => _openProjectContact(store, project),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      );
    }

    // Project conversation view
    if (_isProjectConversation(_activeConversationKey)) {
      return _buildProjectChatView(store, compact: compact);
    }

    return Column(
      children: [
        SizedBox(
          height: 76,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Контакты'),
                  onPressed: () {
                    setState(() => _activeConversationKey = '');
                  },
                ),
              ),
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
          child: _ChatMessagesList(
            key: ValueKey(_activeConversationKey),
            messages: messages,
            owner: store.owner.value,
            compact: compact,
            textFor: _chatMessageText,
            senderLabelFor: _profileLabel,
            stickerAssetFor: _chatStickerAssetUrl,
            imageUrlFor: _chatImageUrl,
            onLongPress: (message) => _openMessageActions(store, message),
            onImageTap: _openPhotoViewer,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyToMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.reply_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ответ: ${_chatMessageText(_replyToMessage!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _replyToMessage = null;
                            _replyToMessageId = null;
                          });
                        },
                        child: const Text('Отмена'),
                      ),
                    ],
                  ),
                ),
              if (_editingMessageId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Редактирование сообщения')),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _editingMessageId = null;
                            _chatInputCtl.clear();
                          });
                        },
                        child: const Text('Отмена'),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Вложение',
                    icon: const Icon(Icons.attach_file),
                    onPressed: () => _openAttachMenu(store),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _chatInputCtl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: _editingMessageId != null
                          ? (_) => _sendTextMessage(store)
                          : null,
                      decoration: InputDecoration(
                        hintText: _editingMessageId == null
                            ? 'Сообщение'
                            : 'Изменить сообщение',
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onLongPressStart: (_) => _startRecord(store),
                    onLongPressEnd: (_) => _stopRecord(store),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.white : null,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed: () => _sendTextMessage(store),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _projectIcon(String icon) {
    switch (icon) {
      case 'code':
        return Icons.code;
      case 'folder':
        return Icons.folder;
      case 'terminal':
      default:
        return Icons.terminal;
    }
  }

  Widget _buildProjectChatView(TaskStore store, {required bool compact}) {
    final project = _projectByConversationKey(_activeConversationKey);
    if (project == null) {
      return const Center(child: Text('Проект не найден'));
    }

    final bridge = _projectBridge;
    final messages = _projectMessages;

    return Column(
      children: [
        // Chat header with back button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() => _activeConversationKey = '');
                  _projectBridge?.dispose();
                  _projectBridge = null;
                  _projectMessages.clear();
                },
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                child: Icon(_projectIcon(project.icon)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    FutureBuilder<String>(
                      future: ProjectBridgeService.getServerAddress(),
                      builder: (context, snapshot) {
                        final addr = snapshot.data ?? '...';
                        return Text(
                          bridge?.isConnected == true
                              ? 'Подключено • $addr'
                              : 'Подключение к $addr...',
                          style: TextStyle(
                            fontSize: 11,
                            color: bridge?.isConnected == true
                                ? Colors.green
                                : Colors.grey,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Запустить bridge',
                icon: const Icon(Icons.power_settings_new),
                onPressed: () => _requestProjectBridgeStart(project),
              ),
              IconButton(
                tooltip: 'Новая сессия',
                icon: const Icon(Icons.add_to_queue),
                onPressed: _startNewProjectSession,
              ),
              IconButton(
                tooltip: 'Остановить DeepSeek',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: _stopProjectPrompt,
              ),
              IconButton(
                tooltip: 'Настроить сервер',
                icon: const Icon(Icons.settings),
                onPressed: () => _openBridgeSettings(),
              ),
            ],
          ),
        ),
        // Messages list
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.terminal,
                        size: 48,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Терминал проекта',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Напишите сообщение для взаимодействия\nс AI-ассистентом в проекте',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).disabledColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          _projectBridge?.dispose();
                          _projectBridge = null;
                          _projectMessages.clear();
                          if (project != null) {
                            _openProjectContact(store, project);
                          }
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Переподключиться'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[messages.length - 1 - index];
                    final isMe = msg.isSent || msg.type == 'send';
                    final isStatus = msg.isStatus || msg.isPong;
                    final isImage = msg.isImage;

                    if (isStatus) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          msg.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).disabledColor,
                          ),
                        ),
                      );
                    }

                    if (isImage && msg.imageBase64.isNotEmpty) {
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  base64Decode(msg.imageBase64),
                                  width: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (context, error, stackTrace) =>
                                          const Icon(Icons.broken_image,
                                              size: 48),
                                ),
                              ),
                              if (msg.imageFilename.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, left: 4),
                                  child: Text(
                                    msg.imageFilename,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).disabledColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  project.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            SelectableText(
                              msg.text,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Input bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Фото в vision',
                onPressed: _sendProjectPhotos,
                icon: const Icon(Icons.image_outlined),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _chatInputCtl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendProjectMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Сообщение',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: _sendProjectMessage,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendProjectMessage() {
    final text = _chatInputCtl.text.trim();
    if (text.isEmpty) {
      return;
    }
    _chatInputCtl.clear();

    _projectBridge?.sendText(text);

    // Show the message immediately in the UI
    if (mounted) {
      setState(() {
        _projectMessages.add(BridgeMessage(
          type: 'send',
          text: text,
        ));
      });
    }
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
          text: 'Фото отправлено в vision: $sent',
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
      return 'Общий';
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
      return _contactLabel(fromContacts.first);
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

  String _contactLabel(ChatContact contact) {
    if (contact.displayName.trim().isNotEmpty) {
      return contact.displayName.trim();
    }
    return _profileLabel(contact.profileKey);
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
      final ok = await channel.invokeMethod<bool>('saveImage', {'url': url});
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
    final urls = _messageImageUrls(message);
    if (urls.isEmpty) {
      return;
    }
    final controller = PageController(initialPage: initialIndex);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: urls.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(urls[index], fit: BoxFit.contain),
                    ),
                  );
                },
              ),
              Positioned(
                top: 24,
                right: 12,
                child: Row(
                  children: [
                    IconButton.filled(
                      onPressed: () => _saveImageToGallery(urls[0]),
                      icon: const Icon(Icons.download),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
                        children: _allKnownContacts(store).map((member) {
                          final profile = member.profileKey;
                          return FilterChip(
                            label: Text(_contactLabel(member)),
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

  Widget _themeMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'Цветовая схема',
      icon: const Icon(Icons.palette_outlined),
      initialValue: widget.selectedThemeKey,
      onSelected: widget.onThemeChanged,
      itemBuilder: (context) {
        return [
          for (final option in _appThemeOptions)
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
                                        return _DashboardView(
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
                                        return _TasksBoard(
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
                                        return _CalendarView(
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
                                            return _FamilyView(
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

class _ChatMessagesList extends StatefulWidget {
  const _ChatMessagesList({
    super.key,
    required this.messages,
    required this.owner,
    required this.compact,
    required this.textFor,
    required this.senderLabelFor,
    required this.stickerAssetFor,
    required this.imageUrlFor,
    required this.onLongPress,
    required this.onImageTap,
    this.replyToMessageId,
    this.onQuoteTap,
  });

  final List<ChatMessage> messages;
  final String owner;
  final bool compact;
  final String Function(ChatMessage message) textFor;
  final String Function(String profile) senderLabelFor;
  final String Function(ChatMessage message) stickerAssetFor;
  final String Function(ChatMessage message) imageUrlFor;
  final void Function(ChatMessage message) onLongPress;
  final void Function(ChatMessage message, int index) onImageTap;
  final String? replyToMessageId;
  final void Function(String quoteText)? onQuoteTap;

  @override
  State<_ChatMessagesList> createState() => _ChatMessagesListState();
}

class _ChatMessagesListState extends State<_ChatMessagesList> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant _ChatMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLast =
        oldWidget.messages.isEmpty ? '' : oldWidget.messages.last.id;
    final newLast = widget.messages.isEmpty ? '' : widget.messages.last.id;
    if (oldLast != newLast ||
        oldWidget.messages.length != widget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) {
      return;
    }
    void jump() {
      if (!_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent + 96,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }

    jump();
    Future<void>.delayed(const Duration(milliseconds: 300), jump);
    Future<void>.delayed(const Duration(milliseconds: 900), jump);
  }

  void scrollToMessage(String messageId) {
    if (!_controller.hasClients) return;
    final index = widget.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final itemHeight = 80.0;
    final estimatedOffset = index * itemHeight;
    final maxScroll = _controller.position.maxScrollExtent;
    final target = estimatedOffset.clamp(0.0, maxScroll);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _navigateToQuote(String quoteText) {
    // Normalize the quote text: remove [photo:...] and [voice] markers
    var cleaned = quoteText
        .replaceAll(RegExp(r'\[photo:.+?\]\s*'), '')
        .replaceAll('[voice] ', '')
        .trim();
    // Extract the part after "Name: "
    final colonIdx = cleaned.indexOf(': ');
    final quotedCore =
        colonIdx >= 0 ? cleaned.substring(colonIdx + 2).trim() : cleaned;
    if (quotedCore.isEmpty) return;
    // Find first message where textFor(msg) starts with or contains quotedCore
    for (final msg in widget.messages) {
      final msgText = widget.textFor(msg);
      if (msgText.startsWith(quotedCore) || msgText.contains(quotedCore)) {
        scrollToMessage(msg.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) {
        final message = widget.messages[index];
        final mine = message.senderProfile == widget.owner;
        return _ChatMessageBubble(
          key: ValueKey(message.id),
          message: message,
          mine: mine,
          compact: widget.compact,
          text: widget.textFor(message),
          senderLabel: widget.senderLabelFor(message.senderProfile),
          stickerAssetUrl: widget.stickerAssetFor(message),
          imageUrl: widget.imageUrlFor(message),
          onLongPress: () => widget.onLongPress(message),
          onImageTap: (index) => widget.onImageTap(message, index),
          onQuoteTap: () {
            final t = widget.textFor(message);
            if (t.startsWith('> ') &&
                t.contains('\n') &&
                message.messageType == 'text') {
              final parts = t.split('\n');
              final qLines = <String>[];
              var inReply = false;
              for (final line in parts) {
                if (!inReply && line.startsWith('> ')) {
                  qLines.add(line.substring(2));
                } else {
                  inReply = true;
                }
              }
              final quote = qLines.join('\n');
              if (quote.isNotEmpty) _navigateToQuote(quote);
            }
          },
        );
      },
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.compact,
    required this.text,
    required this.senderLabel,
    required this.stickerAssetUrl,
    required this.imageUrl,
    required this.onLongPress,
    required this.onImageTap,
    this.onQuoteTap,
  });

  final ChatMessage message;
  final bool mine;
  final bool compact;
  final String text;
  final String senderLabel;
  final String stickerAssetUrl;
  final String imageUrl;
  final VoidCallback onLongPress;
  final void Function(int index) onImageTap;
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final deleted = message.isDeleted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: BoxConstraints(maxWidth: compact ? 320 : 560),
          decoration: BoxDecoration(
            color: deleted
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : mine
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                senderLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              _buildContent(context, deleted, text),
              const SizedBox(height: 4),
              if (message.reactions.isNotEmpty) _buildReactionsRow(context),
              if (message.reactions.isNotEmpty) const SizedBox(height: 4),
              Text(
                _messageFooter(),
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool deleted, String text) {
    if (deleted) {
      return const Text(
        'Сообщение удалено',
        style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF9CA3AF)),
      );
    }
    // Reply quote
    if (text.startsWith('> ') &&
        text.contains('\n') &&
        message.messageType == 'text') {
      final parts = text.split('\n');
      final quoteLines = <String>[];
      final replyLines = <String>[];
      bool inReply = false;
      for (final line in parts) {
        if (!inReply && line.startsWith('> ')) {
          quoteLines.add(line.substring(2));
        } else {
          inReply = true;
          replyLines.add(line);
        }
      }
      final quoteText = quoteLines.join('\n');
      final replyText = replyLines.join('\n');
      // Check for photo preview
      final photoMatch = RegExp(r'\[photo:(.+?)\]').firstMatch(quoteText);
      final hasVoice = quoteText.contains('[voice]');
      final cleanQuote = quoteText
          .replaceAll(RegExp(r'\[photo:.+?\]\s*'), '')
          .replaceAll('[voice] ', '');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              border:
                  Border(left: BorderSide(color: Color(0xFF3B82F6), width: 3)),
            ),
            child: GestureDetector(
              onTap: onQuoteTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photoMatch != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          _bubbleAssetUrl(photoMatch.group(1)!),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 40),
                        ),
                      ),
                    ),
                  if (hasVoice)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child:
                          Icon(Icons.mic, size: 24, color: Color(0xFF6B7280)),
                    ),
                  Expanded(
                    child: Text(
                      cleanQuote,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (replyText.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildTextWithLinks(replyText, context),
          ],
        ],
      );
    }
    if (message.messageType == 'voice') {
      return _buildVoiceBubble(context);
    }
    if (message.messageType == 'sticker') {
      if (stickerAssetUrl.isNotEmpty &&
          !stickerAssetUrl.startsWith('emoji://')) {
        return Image.network(
          stickerAssetUrl,
          fit: BoxFit.contain,
          width: compact ? 160 : 220,
          height: compact ? 160 : 220,
          errorBuilder: (context, error, stackTrace) {
            return Text(text, style: const TextStyle(fontSize: 34));
          },
        );
      }
      return Text(text, style: const TextStyle(fontSize: 34));
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      final urls = _messageImageUrls();
      if (urls.isEmpty) {
        return Text(text.isEmpty ? 'Изображение' : text);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageGrid(urls),
          if (text.trim().isNotEmpty) const SizedBox(height: 6),
          if (text.trim().isNotEmpty) Text(text),
        ],
      );
    }
    if (message.messageType == 'text') {
      return _buildTextWithLinks(text, context);
    }
    return Text(text);
  }

  static final RegExp _urlRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+\.[^\s]+)');

  Widget _buildTextWithLinks(String text, BuildContext context) {
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text);
    }
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      final uri = Uri.tryParse(url.startsWith('www.') ? 'https://$url' : url);
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return Text.rich(TextSpan(children: spans));
  }

  List<String> _messageImageUrls() {
    final attachments = message.attachments
        .where(
            (item) => item.kind == 'image' && item.assetUrl.trim().isNotEmpty)
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.assetUrl).toList();
    }
    return imageUrl.trim().isEmpty ? const [] : [imageUrl];
  }

  Widget _buildImageGrid(List<String> urls) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < urls.length; i++)
          GestureDetector(
            onTap: () => onImageTap(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _bubbleAssetUrl(urls[i]),
                fit: BoxFit.cover,
                width: urls.length == 1
                    ? (compact ? 260 : 420)
                    : (compact ? 120 : 160),
                height: urls.length == 1 ? null : (compact ? 120 : 160),
                errorBuilder: (context, error, stackTrace) {
                  return SelectableText(
                    urls[i],
                    style:
                        const TextStyle(decoration: TextDecoration.underline),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVoiceBubble(BuildContext context) {
    final ms = (message.imageMeta['duration_ms'] as int?) ?? 0;
    final d = Duration(milliseconds: ms);
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        const ch = MethodChannel('family_todo_mobile/voice');
        ch.invokeMethod('playVoice', {'url': _bubbleAssetUrl(imageUrl)});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow,
                size: 24,
                color: mine ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: mine ? cs.onPrimaryContainer : cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  String _bubbleAssetUrl(String raw) {
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return 'http://31.129.97.211$value';
    }
    return value;
  }

  Widget _buildReactionsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: message.reactions.map((reaction) {
        final isMyReaction = message.myReaction == reaction.reaction;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isMyReaction
                ? cs.primaryContainer.withOpacity(0.5)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border:
                isMyReaction ? Border.all(color: cs.primary, width: 1) : null,
          ),
          child: Text(
            '${reaction.reaction} ${reaction.count}',
            style: TextStyle(
              fontSize: 13,
              color: isMyReaction
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF475569),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _messageFooter() {
    if ((message.editedAt ?? '').isNotEmpty) {
      return '${message.createdAt} · изменено';
    }
    return message.createdAt;
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.vm,
    required this.labelFor,
    required this.onOpenCalendar,
  });

  final DashboardVm vm;
  final String Function(String profile) labelFor;
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
                '${task.dueDate} ${task.time} - ${labelFor(task.ownerKey)} - ${workflowLabel(task.workflowStatus)}',
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
    required this.labelFor,
    required this.onDateChange,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime selectedDate;
  final List<TaskItem> tasksForSelectedDate;
  final String Function(String profile) labelFor;
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
                  labelFor: labelFor,
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
    required this.labelFor,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDrop,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final String Function(String profile) labelFor;
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
                              labelFor: labelFor,
                              onEdit: () async {},
                              onDelete: () async {},
                              onDoneToggle: () async {},
                            ),
                          ),
                        ),
                        childWhenDragging: const SizedBox.shrink(),
                        child: _TaskCard(
                          item: item,
                          labelFor: labelFor,
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
    required this.labelFor,
    required this.selectionMode,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onDropStatus,
    required this.onEdit,
    required this.onDelete,
    required this.onDoneToggle,
  });

  final Map<String, List<TaskItem>> byStatus;
  final String Function(String profile) labelFor;
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

  static Color _columnColor(String status) {
    switch (status) {
      case 'todo':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'in_review':
        return const Color(0xFF8B5CF6);
      case 'done':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: SizedBox(
            width: 4 * 340,
            height: constraints.maxHeight,
            child: Row(
              children: _titles.keys.map((status) {
                final items = byStatus[status] ?? const <TaskItem>[];
                final colColor = _columnColor(status);
                return SizedBox(
                  width: 330,
                  child: Card(
                    margin: const EdgeInsets.only(right: 10),
                    elevation: 0,
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colColor, width: 1),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_titles[status]} (${items.length})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: colColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: DragTarget<TaskItem>(
                              onAcceptWithDetails: (details) =>
                                  onDropStatus(details.data, status),
                              builder: (dragCtx, candidateData, rejectedData) {
                                final isHovering = candidateData.isNotEmpty;
                                if (items.isEmpty && !isHovering) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inbox_outlined,
                                              size: 32,
                                              color: colColor.withAlpha(100)),
                                          const SizedBox(height: 8),
                                          Text('Нет задач',
                                              style: TextStyle(
                                                  color: Theme.of(dragCtx)
                                                      .colorScheme
                                                      .onSurface
                                                      .withOpacity(0.4))),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return ListView(
                                  children: [
                                    if (isHovering)
                                      Container(
                                        height: 60,
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                              color: colColor,
                                              width: 2,
                                              strokeAlign:
                                                  BorderSide.strokeAlignInside),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          color: colColor.withAlpha(15),
                                        ),
                                        child: Center(
                                            child: Icon(Icons.add,
                                                color: colColor)),
                                      ),
                                    for (final item in items)
                                      LongPressDraggable<TaskItem>(
                                        data: item,
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width: 280,
                                            child: _TaskCard(
                                              item: item,
                                              labelFor: labelFor,
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
                                          labelFor: labelFor,
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
    required this.labelFor,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TaskItem> familyTasks;
  final String familyFilter;
  final String Function(String profile) labelFor;
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
                  labelFor: labelFor,
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
    this.labelFor,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionToggle,
  });

  final TaskItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectionToggle;
  final String Function(String profile)? labelFor;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  final Future<void> Function() onDoneToggle;

  static Color _statusColor(String status) {
    switch (status) {
      case 'todo':
        return const Color(0xFF3B82F6);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'in_review':
        return const Color(0xFF8B5CF6);
      case 'done':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  static Widget _statusChip(String status, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status).withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _statusColor(status), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _statusColor(status),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolveLabel = labelFor ?? profileLabel;
    final statusColor = _statusColor(item.workflowStatus);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F2937) : const Color(0xFFFFFFFF);
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: statusColor.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(
          left: BorderSide(color: statusColor, width: 4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: selectionMode ? onSelectionToggle : () => onEdit(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Checkbox(
                        value: selected,
                        onChanged: (_) => onSelectionToggle?.call(),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusChip(
                    item.workflowStatus,
                    workflowLabel(item.workflowStatus),
                  ),
                ],
              ),
              if (item.dueDate.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      '${item.dueDate} ${item.time}'.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ],
              if (item.details.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: textColor.withOpacity(0.7)),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (item.assignees.isNotEmpty)
                    ...item.assignees.take(3).map((assignee) {
                      final initials = resolveLabel(assignee).isNotEmpty
                          ? resolveLabel(assignee).substring(0, 1).toUpperCase()
                          : '?';
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: statusColor.withAlpha(40),
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      resolveLabel(item.ownerKey),
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withOpacity(0.45),
                      ),
                    ),
                  ),
                  if (!selectionMode) ...[
                    IconButton(
                      tooltip: 'Выполнить/отменить',
                      iconSize: 20,
                      icon: Icon(
                        item.workflowStatus == 'done'
                            ? Icons.undo
                            : Icons.check_circle,
                        color: statusColor,
                      ),
                      onPressed: () => onDoneToggle(),
                    ),
                    IconButton(
                      tooltip: 'Удалить',
                      iconSize: 20,
                      icon: Icon(Icons.delete_outline,
                          color: textColor.withOpacity(0.5)),
                      onPressed: () => onDelete(),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
