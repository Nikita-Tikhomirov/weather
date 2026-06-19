import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_config.dart';
import '../../app/app_labels.dart';
import '../../app/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'home_attachment_labels.dart';
import 'home_chat_action_labels.dart';
import 'home_dashboard_labels.dart';
import 'home_group_chat_labels.dart';
import 'home_call_history.dart';
import 'home_misc_labels.dart';
import 'home_navigation_widget.dart';
import 'home_project_chat_agent_labels.dart';
import 'home_project_data_labels.dart';
import 'home_project_status_sheet.dart';
import 'home_voice_recorder_messages.dart';
import '../../shared/utils/avatar_url_resolver.dart';
import 'home_helpers.dart';
import 'desktop_shell_labels.dart';
import '../admin/admin_access_page.dart';
import '../chat/active_call_banner.dart';
import '../chat/call_screen.dart';
import '../chat/chat_photo_viewer.dart';
import '../chat/messenger_page.dart';
import '../chat/sticker_picker_sheet.dart';
import '../projects/project_file_browser.dart';
import '../projects/project_chat_view.dart';
import '../projects/chat_task_draft_editor_sheet.dart';
import '../projects/projects_and_groups_screen.dart';
import '../profile/profile_page.dart';
import '../tasks/calendar_view.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/tasks_board.dart';
import '../workspaces/codewhale_workspaces_page.dart';
import '../../models/call_models.dart';
import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/family_group.dart';
import '../../models/project_contact.dart';
import '../../models/project_file.dart';
import '../../models/task_item.dart';
import '../../models/task_project.dart';
import '../../services/api_client.dart';
import '../../services/call_service.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/codewhale_bridge_service.dart';
import '../../services/desktop_process_host_service.dart';
import '../../services/gallery_image_saver.dart';
import '../../services/local_db.dart';
import '../../services/desktop_theme_service.dart';
import '../../services/project_access.dart';
import '../../services/project_chat_agent_service.dart';
import '../../services/profile_init_service.dart';
import '../../services/project_bridge_service.dart';
import '../../services/push_notification_handler.dart';
import '../../services/service_locator.dart';
import '../../services/sync_loop_service.dart';
import '../../services/task_agent_automation_service.dart';
import '../../services/voice_recorder_service.dart';
import '../../state/task_store.dart';

part 'desktop_shell.dart';
part 'share_receiver.dart';
part 'projects_data.dart';
part 'home_dashboard_section.dart';
part 'home_navigation.dart';
part 'home_chat_section.dart';

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
  DesktopThemeService? _desktopThemeService;
  DesktopProcessHostService? _desktopProcessHostService;
  SyncLoopService? _syncLoops;
  TaskAgentAutomationService? _taskAgentAutomation;
  PushNotificationHandler? _pushHandler;
  VoiceRecorderService? _voiceRecorder;
  bool _desktopLogExpanded = false;
  DateTime _desktopMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  final TextEditingController _chatInputCtl = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  ChatRealtimeService? _chatRealtime;
  CallService? _callService;
  StreamSubscription<CallState>? _callStateSub;
  CallSession? _activeCallSession;
  CallSession? _pendingIncomingCallSession;
  CallState _activeCallState = CallState.idle;
  bool _callScreenOpen = false;
  bool _chatLoading = false;
  String? _editingMessageId;
  List<ChatContact> _chatContacts = const <ChatContact>[];
  List<ChatContact> _phoneContacts = const <ChatContact>[];
  List<ChatContact> _familyMembers = const <ChatContact>[];
  List<ProjectContact> _projectContacts = const <ProjectContact>[];
  ProjectBridgeService? _projectBridge;
  CodeWhaleBridgeService? _projectChatAgentBridge;
  ProjectChatAgentBridgeRunner? _projectChatAgentRunner;
  String _projectChatAgentSessionId = '';
  String _pendingProjectChatAgentPrompt = '';
  String _pendingProjectChatAgentWorkspaceId = '';
  Completer<String>? _projectChatAgentResponseCompleter;
  StringBuffer _projectChatAgentResponseBuffer = StringBuffer();
  final Map<String, ProjectControlSnapshot> _projectControlSnapshots =
      <String, ProjectControlSnapshot>{};
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
  final Map<String, String> _chatOlderCursors = <String, String>{};
  final Set<String> _chatOlderLoading = <String>{};
  final Set<String> _chatOlderExhausted = <String>{};
  final Set<String> _recordedCallHistoryIds = <String>{};
  String _activeConversationKey = '';
  String _currentProfileDisplayName = '';
  String _currentProfilePhone = '';
  String? _currentProfileAvatarUrl;
  UserAccessPolicy _accessPolicy = const UserAccessPolicy.messengerOnly();
  final Map<String, String> _profileAvatarUrls = <String, String>{};
  ChatMessage? _replyToMessage;
  bool _pushAlreadyRouted = false;

  HomeChatActionLabels get _chatActionLabels =>
      HomeChatActionLabels(AppLocalizations.of(context));
  HomeGroupChatLabels get _groupChatLabels =>
      HomeGroupChatLabels(AppLocalizations.of(context));
  HomeAttachmentLabels get _attachmentLabels =>
      HomeAttachmentLabels(AppLocalizations.of(context));
  HomeMiscLabels get _miscLabels =>
      HomeMiscLabels(AppLocalizations.of(context));
  HomeProjectDataLabels get _projectDataLabels =>
      HomeProjectDataLabels(AppLocalizations.of(context));
  HomeProjectChatAgentLabels get _projectChatAgentLabels =>
      HomeProjectChatAgentLabels(AppLocalizations.of(context));

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
    _currentProfileAvatarUrl = prefs.getString(
      '${AppConfig.prefAvatarPrefix}${savedOwner.isNotEmpty ? savedOwner : 'default'}',
    );
    final locator = ServiceLocator.instance;
    final api = locator.api;
    String? owner;
    final savedPhone = prefs.getString('profile_phone')?.trim() ?? '';
    final profileInit = ProfileInitService(
      api: api,
      onProfileChanged: _setProfileInfo,
    );
    if (savedPhone.isNotEmpty) {
      try {
        owner = await profileInit.restoreProfileByPhone(
          prefs,
          savedPhone,
          _currentProfileDisplayName,
        );
      } catch (e, st) {
        debugPrint('[home] restore profile by phone error: $e\n$st');
        if (savedOwner.isNotEmpty) {
          owner = savedOwner;
        } else {
          if (!mounted) return;
          owner = await ProfileInitService.promptForInitialProfile(
            context,
            api,
            _setProfileInfo,
          );
        }
      }
    } else if (savedOwner.isNotEmpty) {
      owner = savedOwner;
    } else {
      if (!mounted) return;
      owner = await ProfileInitService.promptForInitialProfile(
        context,
        api,
        _setProfileInfo,
      );
    }
    if (!mounted || owner == null || owner.isEmpty) {
      return;
    }

    // Load avatar for resolved owner
    final avatarKey = 'avatar_$owner';
    _currentProfileAvatarUrl = prefs.getString(avatarKey);
    if (mounted) setState(() {});

    final store = locator.taskStore;
    await store.initialize(initialOwner: owner);
    await _loadAccessPolicy(api, owner);
    store.onWorkflowMoved = _handleTaskWorkflowMoved;
    if (!_accessPolicy.canUseTaskManager) {
      store.setPage(2);
    }
    if (_isDesktopWindows) {
      await _initDesktopServices(store, owner);
    }
    _pushHandler = PushNotificationHandler(
      api: api,
      owner: owner,
      onDiagnosticsChanged: (_) {},
      onShowDiagnosticsDialog: _showFcmDiagnosticsDialog,
      onNavigateToTasks: () => store.setPage(1),
      onNavigateToMessenger: () => store.setPage(4),
      onOpenConversation: (key) async {
        _pushAlreadyRouted = true;
        store.setPage(4);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await _openConversation(store, key);
        }
      },
      onIncomingCall: _receiveIncomingCall,
      onSyncDelta: ({required bool showErrors}) =>
          _safeSyncDelta(store, showErrors: showErrors),
      onRefreshActiveConversation: ({
        required bool useNetwork,
        required bool quiet,
      }) =>
          _refreshActiveConversation(
        store,
        useNetwork: useNetwork,
        quiet: quiet,
      ),
      getActiveConversationKey: () => _activeConversationKey,
      getIsProjectConversation: isProjectConversation,
      getPageIndex: () => store.pageIndex.value,
      shouldSuppressChatNotification: (conversationKey) {
        final canonical = canonicalConversationKey(conversationKey);
        return store.pageIndex.value == 4 &&
            _activeConversationKey == canonical;
      },
    )..bindFcm();
    await _safeSyncFull(store, showErrors: false);
    await _initChat(store);
    _initShareReceiver(store);
    _chatInputCtl.addListener(() => _onChatInputChanged(store));
    _syncLoops = SyncLoopService(
      store: store,
      callService: _callService,
      onRetryPendingMessages: _retryPendingMessages,
    )..start();
    if (!mounted) {
      store.dispose();
      return;
    }
    setState(() => _store = store);

    final l10n = AppLocalizations.of(context);
    _voiceRecorder = VoiceRecorderService(
      store: store,
      messages: buildHomeVoiceRecorderMessages(l10n),
      onRecordingChanged: (_) {
        if (mounted) setState(() {});
      },
      onShowSnackBar: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
        }
      },
      getActiveConversationKey: () => _activeConversationKey,
      onVoiceMessageSent: _appendSentChatMessage,
    );

    await _pushHandler?.processPendingPush();
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

  // ── Thin wrappers used by the desktop-shell part file ──
  // These exist so the extension on _HomePageState in desktop_shell.dart
  // can mutate state without calling the protected setState() directly.

  void _toggleDesktopLogExpanded() {
    setState(() => _desktopLogExpanded = !_desktopLogExpanded);
  }

  void _goDesktopMonthPrev() {
    setState(
      () =>
          _desktopMonth = DateTime(_desktopMonth.year, _desktopMonth.month - 1),
    );
  }

  void _goDesktopMonthNext() {
    setState(
      () =>
          _desktopMonth = DateTime(_desktopMonth.year, _desktopMonth.month + 1),
    );
  }

  void _goDesktopMonthToday() {
    setState(() {
      final now = DateTime.now();
      _desktopMonth = DateTime(now.year, now.month);
      _store?.setSelectedDate(now);
    });
  }

  void _goCalendarMonthPrev() {
    setState(
      () => _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month - 1),
    );
  }

  void _goCalendarMonthNext() {
    setState(
      () => _calendarMonth =
          DateTime(_calendarMonth.year, _calendarMonth.month + 1),
    );
  }

  void _goCalendarMonthToday() {
    setState(() {
      final now = DateTime.now();
      _calendarMonth = DateTime(now.year, now.month);
      _store?.setSelectedDate(now);
    });
  }

  // Thin wrappers used by part files

  void _setActiveConversation(String key) {
    setState(() => _activeConversationKey = key);
  }

  void _clearActiveConversation() {
    _setActiveConversation('');
  }

  void _clearChatReply() {
    setState(() => _replyToMessage = null);
  }

  void _cancelChatEdit() {
    setState(() {
      _editingMessageId = null;
      _chatInputCtl.clear();
    });
  }

  void _markChatMessagesChanged() {
    setState(() {});
  }

  void _setProfileInfo(String displayName, String phone) {
    setState(() {
      _currentProfileDisplayName = displayName;
      _currentProfilePhone = phone;
    });
  }

  Future<void> _loadAccessPolicy(ApiClient api, String owner) async {
    try {
      final access = await api.fetchAccessPolicy(
        actorProfile: owner,
        phone: _currentProfilePhone,
      );
      if (!mounted) {
        _accessPolicy = access;
        return;
      }
      setState(() => _accessPolicy = access);
    } catch (e, st) {
      debugPrint('[home] access policy error: $e\n$st');
      if (!mounted) {
        _accessPolicy = const UserAccessPolicy.messengerOnly();
        return;
      }
      setState(() => _accessPolicy = const UserAccessPolicy.messengerOnly());
    }
  }

  void _notifyCallEnded() {
    if (!mounted) return;
    setState(() {
      _activeCallState = CallState.ended;
      _activeCallSession = null;
      _pendingIncomingCallSession = null;
    });
  }

  // Thin wrappers used by chat_init.dart

  void _setChatLoading(bool value) {
    setState(() => _chatLoading = value);
  }

  void _setChatBootstrapState(
    List<ChatContact> contacts,
    List<ChatConversation> conversations,
    List<StickerPack> stickerPacks,
  ) {
    setState(() {
      _chatContacts = contacts;
      _chatConversations = conversations;
      _chatStickerPacks = stickerPacks;
    });
  }

  void _removeConversationState(String key) {
    setState(() {
      _chatConversations.removeWhere((item) => item.conversationKey == key);
      _chatMessagesByConversation.remove(key);
      if (_activeConversationKey == key) {
        _activeConversationKey = '';
      }
    });
  }

  void _setChatInitState(
    List<ChatContact> contacts,
    List<ChatConversation> conversations,
    List<StickerPack> stickerPacks,
    bool clearActive,
  ) {
    setState(() {
      _chatContacts = contacts;
      _chatConversations = conversations;
      _chatStickerPacks = stickerPacks;
      if (clearActive) {
        _activeConversationKey = '';
      }
    });
  }

  // Thin wrappers used by projects_data.dart

  void _setProjectContacts(List<ProjectContact> contacts) {
    setState(() => _projectContacts = contacts);
  }

  void _setProjectMessagesList(List<BridgeMessage> msgs) {
    setState(() {
      _projectMessages
        ..clear()
        ..addAll(msgs);
    });
  }

  void _addProjectMessages(List<BridgeMessage> msgs) {
    setState(() => _projectMessages.addAll(msgs));
  }

  void _addProjectMessage(BridgeMessage msg) {
    setState(() => _projectMessages.add(msg));
  }

  void _resetProjectMessages(BridgeMessage msg) {
    setState(() {
      _projectMessages
        ..clear()
        ..add(msg);
    });
  }

  bool _mergeStreamingProjectOutput(BridgeMessage msg) {
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
    return handled;
  }

  void _setProjectBridge(ProjectBridgeService? bridge) {
    setState(() => _projectBridge = bridge);
  }

  void _setProjectFileBrowserLoading({
    required String path,
    BridgeMessage? statusMessage,
  }) {
    setState(() {
      _projectFileTreePath = path;
      _projectFiles = [];
      _projectFilesLoading = true;
      if (statusMessage != null) {
        _projectMessages.add(statusMessage);
      }
    });
  }

  void _setProjectFiles(List<ProjectFileNode> files) {
    setState(() {
      _projectFiles = files;
      _projectFilesLoading = false;
    });
    _fileSheetSetState?.call(() {});
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
        _chatOlderCursors[canonicalKey] = snapshot.nextCursor!;
        _chatOlderExhausted.remove(canonicalKey);
        await db.saveChatCursor(
          conversationKey: canonicalKey,
          cursor: snapshot.nextCursor!,
        );
      } else {
        _chatOlderCursors.remove(canonicalKey);
        _chatOlderExhausted.add(canonicalKey);
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
        _typingUsers[canonicalKey] ?? const <String>{},
        nextTyping,
      );
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
          SnackBar(content: Text(_miscLabels.chatRefreshFailed(error))),
        );
      }
    }
  }

  Future<void> _loadOlderChatMessages(TaskStore store) async {
    final conversationKey = canonicalConversationKey(_activeConversationKey);
    if (conversationKey.isEmpty ||
        _chatOlderLoading.contains(conversationKey) ||
        _chatOlderExhausted.contains(conversationKey)) {
      return;
    }

    final cursor = _chatOlderCursors[conversationKey];
    if (cursor == null || cursor.isEmpty) {
      _chatOlderExhausted.add(conversationKey);
      return;
    }

    setState(() {
      _chatOlderLoading.add(conversationKey);
    });

    try {
      final snapshot = await store.repository.api.chatFetchMessages(
        actorProfile: store.owner.value,
        conversationKey: conversationKey,
        cursor: cursor,
        limit: 50,
      );
      final canonicalKey = snapshot.messages.isEmpty
          ? conversationKey
          : canonicalConversationKey(snapshot.messages.first.conversationKey);
      await store.repository.db.upsertMessages(snapshot.messages);

      if (snapshot.nextCursor != null && snapshot.nextCursor!.isNotEmpty) {
        _chatOlderCursors[canonicalKey] = snapshot.nextCursor!;
        _chatOlderExhausted.remove(canonicalKey);
        await store.repository.db.saveChatCursor(
          conversationKey: canonicalKey,
          cursor: snapshot.nextCursor!,
        );
      } else {
        _chatOlderCursors.remove(canonicalKey);
        _chatOlderExhausted.add(canonicalKey);
      }

      final existing =
          _chatMessagesByConversation[canonicalKey] ?? const <ChatMessage>[];
      final byId = <String, ChatMessage>{
        for (final message in [...snapshot.messages, ...existing])
          message.id: message,
      };
      final merged = byId.values.toList()
        ..sort((a, b) {
          final byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
      if (mounted) {
        setState(() {
          _chatMessagesByConversation[canonicalKey] = merged;
          _chatOlderLoading.remove(conversationKey);
          _chatOlderLoading.remove(canonicalKey);
        });
      }
    } catch (e, st) {
      debugPrint('[chat] load older messages error: $e\n$st');
      if (mounted) {
        setState(() {
          _chatOlderLoading.remove(conversationKey);
        });
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
      final alreadyResolved = merged.any(
        (item) =>
            item.id == message.id ||
            (message.clientMessageId != null &&
                message.clientMessageId!.isNotEmpty &&
                item.clientMessageId == message.clientMessageId),
      );
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
    TaskStore store,
    String conversationKey,
  ) async {
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
    final labels = _miscLabels;
    final titleCtl = TextEditingController(text: labels.newGroup);
    final contacts = _phoneContacts.isEmpty ? _chatContacts : _phoneContacts;
    final created = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtl,
                      decoration:
                          InputDecoration(labelText: labels.groupNameLabel),
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
                      label: Text(labels.create),
                    ),
                  ],
                ),
              ),
            );
          },
        );
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
          SnackBar(
            content: Text(
              _miscLabels.contactAddedToFamily(contactLabel(contact)),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_miscLabels.addToFamilyFailed(error))),
        );
      }
    }
  }

  // ── Chat init methods (moved from chat_init.dart part file) ──

  Future<void> _refreshChatBootstrap(TaskStore store) async {
    try {
      final bootstrap = await store.repository.api.chatBootstrap(
        actorProfile: store.owner.value,
      );
      await store.repository.db.replaceConversations(bootstrap.conversations);
      await store.repository.db.replaceStickerPacks(bootstrap.stickerPacks);

      await _restoreLocalGroupAvatars(store, bootstrap.conversations);

      final mergedConversations = await store.repository.db.readConversations();

      final contacts = bootstrap.contacts;
      if (mounted) {
        await _saveAvatarUrlsFromContacts(contacts);
        await _loadProfileAvatars([
          ...contacts.map((item) => item.profileKey),
          ...mergedConversations.expand((item) => item.members),
        ]);
        _setChatBootstrapState(
          contacts,
          mergedConversations,
          bootstrap.stickerPacks,
        );
      }
    } catch (e, st) {
      debugPrint('[chat] bootstrap refresh error: $e\n$st');
    }
  }

  Future<void> _refreshMessengerContacts(TaskStore store) async {
    await _refreshChatBootstrap(store);
    await _loadPhoneContacts(store);
  }

  Future<void> _restoreLocalGroupAvatars(
    TaskStore store,
    List<ChatConversation> serverConversations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final conv in serverConversations) {
      final key = 'group_avatar_${conv.conversationKey}';
      final savedUrl = prefs.getString(key);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        await store.repository.db.upsertConversation(
          ChatConversation(
            conversationKey: conv.conversationKey,
            kind: conv.kind,
            title: conv.title,
            members: conv.members,
            avatarUrl: savedUrl,
          ),
        );
      }
    }
  }

  Future<void> _removeLocalConversation(
    TaskStore store,
    String conversationKey,
  ) async {
    final key = conversationKey.trim();
    if (key.isEmpty) return;
    await store.repository.db.deleteConversation(key);
    if (!mounted) return;
    _removeConversationState(key);
  }

  Future<void> _initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    final pushConversationKey =
        _pushAlreadyRouted ? _activeConversationKey : '';

    _setChatLoading(true);
    _chatMessagesByConversation.clear();
    _chatOlderCursors.clear();
    _chatOlderLoading.clear();
    _chatOlderExhausted.clear();
    if (!_pushAlreadyRouted) {
      _setActiveConversation('');
    }

    try {
      final bootstrap = await api.chatBootstrap(actorProfile: actor);
      await db.replaceConversations(bootstrap.conversations);
      await db.replaceStickerPacks(bootstrap.stickerPacks);

      await _restoreLocalGroupAvatars(store, bootstrap.conversations);

      final conversations = await db.readConversations();
      final stickerPacks = await db.readStickerPacks();

      if (!mounted) return;
      await _saveAvatarUrlsFromContacts(bootstrap.contacts);
      await _loadProfileAvatars([
        ...bootstrap.contacts.map((item) => item.profileKey),
        ...conversations.expand((item) => item.members),
      ]);

      List<ChatConversation> finalConversations = conversations;
      if (pushConversationKey.isNotEmpty &&
          !finalConversations
              .any((c) => c.conversationKey == pushConversationKey) &&
          !isProjectConversation(pushConversationKey)) {
        finalConversations = [
          ...finalConversations,
          ChatConversation(
            conversationKey: pushConversationKey,
            kind: 'direct',
            title: '',
            members: pushConversationKey.startsWith('dm:')
                ? pushConversationKey.split(':').skip(1).toList()
                : [store.owner.value],
          ),
        ];
      }

      _setChatInitState(
        bootstrap.contacts,
        finalConversations,
        stickerPacks,
        !_pushAlreadyRouted,
      );

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

      if (pushConversationKey.isNotEmpty && mounted) {
        await _refreshConversation(
          store,
          pushConversationKey,
          useNetwork: true,
          quiet: true,
        );
      }

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
          SnackBar(content: Text(_miscLabels.chatUnavailable(error))),
        );
      }
    } finally {
      if (mounted) {
        _setChatLoading(false);
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
    } catch (e, st) {
      debugPrint('[contacts] load phone contacts error: $e\n$st');
      if (mounted) {
        setState(() {
          _phoneContacts = _chatContacts;
        });
      }
    }
  }

  void _replaceCallService({
    required ApiClient api,
    required String actorProfile,
  }) {
    _callStateSub?.cancel();
    _callStateSub = null;
    _callService?.dispose();
    _callService = CallService(api: api, actorProfile: actorProfile)
      ..onIncomingCall = _handleIncomingCall
      ..onCallEnded = _notifyCallEnded;
    _callStateSub = _callService!.onStateChange.listen(_handleCallStateChanged);
    // Update the sync loop service's call service reference
    if (_syncLoops != null) {
      _syncLoops!.callService = _callService;
    }
    final pending = _pendingIncomingCallSession;
    if (pending != null) {
      _pendingIncomingCallSession = null;
      _callService!.notifyIncomingCall(pending);
    }
  }

  void _handleCallStateChanged(CallState state) {
    final previousState = _activeCallState;
    final session = _callService?.currentSession ?? _activeCallSession;
    if (state == CallState.ended && session != null) {
      unawaited(_recordCallHistoryMessage(session, previousState));
    }
    if (!mounted) return;
    setState(() {
      _activeCallState = state;
      if (state == CallState.idle || state == CallState.ended) {
        _activeCallSession = null;
        _pendingIncomingCallSession = null;
      } else {
        _activeCallSession = session;
      }
    });
  }

  Future<void> _recordCallHistoryMessage(
    CallSession session,
    CallState previousState,
  ) async {
    final store = _store;
    final owner = store?.owner.value ?? '';
    final sessionId = session.sessionId.trim();
    final conversationKey = canonicalConversationKey(session.conversationKey);
    if (store == null ||
        owner.isEmpty ||
        sessionId.isEmpty ||
        conversationKey.isEmpty ||
        previousState == CallState.idle ||
        previousState == CallState.ended) {
      return;
    }

    final status =
        previousState == CallState.connected ? 'completed' : 'missed';
    final historyKey = '$sessionId:$status';
    if (!_recordedCallHistoryIds.add(historyKey)) {
      return;
    }

    final message = buildCallHistoryMessage(
      session: session.copyWith(conversationKey: conversationKey),
      owner: owner,
      previousState: previousState,
      endedAt: DateTime.now(),
    );
    _appendSentChatMessage(message);

    final db = store.repository.db;
    final api = store.repository.api;
    await db.upsertMessages([message]);
    try {
      final sent = await api.chatSendMessage(
        actorProfile: owner,
        conversationKey: conversationKey,
        messageType: 'call',
        text: message.text,
        imageMeta: message.imageMeta,
        clientMessageId: message.clientMessageId,
      );
      final displayMessage = sent.copyWith(
        deliveryStatus: 'sent',
        text: sent.text.trim().isEmpty ? message.text : sent.text,
        imageMeta: sent.imageMeta.isEmpty ? message.imageMeta : sent.imageMeta,
      );
      await db.upsertMessages([displayMessage]);
      _appendSentChatMessage(displayMessage);
    } catch (e, st) {
      debugPrint('[call] history message send error: $e\n$st');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncErrorMessage(error))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncErrorMessage(error))),
        );
      }
    }
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
            imageMeta: m.imageMeta,
            clientMessageId: m.clientMessageId,
            attachments: m.attachments,
          );
          await db.upsertMessages([sent]);
          msgs[i] = sent.copyWith(deliveryStatus: 'sent');
          _chatMessagesByConversation[convKey] = msgs;
        } catch (e, st) {
          debugPrint('[push] retry send error: $e\n$st');
          // Will retry next cycle
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _appendSentChatMessage(ChatMessage message) {
    if (!mounted) return;
    final conversationKey = canonicalConversationKey(message.conversationKey);
    final current = List<ChatMessage>.from(
      _chatMessagesByConversation[conversationKey] ?? const <ChatMessage>[],
    );
    current.removeWhere(
      (item) =>
          item.id == message.id ||
          (message.clientMessageId != null &&
              message.clientMessageId!.isNotEmpty &&
              item.clientMessageId == message.clientMessageId),
    );
    current.add(message);
    current.sort((a, b) {
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
    setState(() {
      _chatMessagesByConversation[conversationKey] = current;
      if (_activeConversationKey.isNotEmpty &&
          canonicalConversationKey(_activeConversationKey) == conversationKey) {
        _activeConversationKey = conversationKey;
      }
    });
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
      } catch (_) {
        // silently ignored — non-critical operation
      }
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
      final boundProject = _projectForBoundGroupConversation(
        store,
        conversationKey,
      );
      if (editingId == null &&
          boundProject != null &&
          ProjectChatAgentService.isAddressed(finalText)) {
        unawaited(
          _handleProjectChatAgentMention(store, boundProject, finalText),
        );
      }
    } catch (e, st) {
      debugPrint('[chat] send message error: $e\n$st');
      // Message stays in 'sending' state — retry on next sync
    }
  }

  Future<void> _shareMessage(TaskStore store, ChatMessage message) async {
    if (message.isDeleted) return;
    final labels = _chatActionLabels;
    final allContacts = _allKnownContacts(store);
    // Build list of unique contacts excluding self
    final targets =
        allContacts.where((c) => c.profileKey != store.owner.value).toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.noForwardTargets)),
        );
      }
      return;
    }
    final selected = await showDialog<ChatContact>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.shareWithTitle),
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
            child: Text(labels.cancel),
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
          text: labels.forwardedSticker(senderLabel),
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
                      sortOrder: 0,
                    ),
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
                : labels.forwardedPhoto(senderLabel),
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
      await _refreshConversation(
        store,
        conversationKey,
        useNetwork: true,
        quiet: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.forwardedTo(contactLabel(selected)))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.forwardFailed(error))),
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
    final labels = _chatActionLabels;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(labels.deleteMessageTitle),
          content: Text(labels.deleteMessageBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(labels.delete),
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
        SnackBar(content: Text(labels.deleteFailed(error))),
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
    final labels = _chatActionLabels;
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
                  title: Text(labels.removeReaction),
                  onTap: () => Navigator.of(sheetContext).pop('react:'),
                ),
              if (message.messageType == 'text' &&
                  message.senderProfile == store.owner.value)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(labels.edit),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: Text(labels.reply),
                onTap: () => Navigator.of(sheetContext).pop('reply'),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(labels.share),
                onTap: () => Navigator.of(sheetContext).pop('share'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(labels.delete),
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
        final labels = _chatActionLabels;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.reactionFailed(error))),
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
        SnackBar(content: Text(_chatActionLabels.stickerSendFailed(error))),
      );
    }
  }

  Future<void> _openManageGroupSheet(
    TaskStore store,
    ChatConversation conv,
  ) async {
    final labels = _groupChatLabels;
    final members = List<String>.from(conv.members);
    final initialAvatarUrl = conv.avatarUrl;
    final canManage = conv.kind == 'group' ||
        conv.conversationKey == 'group:common' ||
        conv.conversationKey.startsWith('grp:');
    String? avatarUrl = initialAvatarUrl;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Group avatar — tap to change
                    GestureDetector(
                      onTap: canManage
                          ? () async {
                              final url =
                                  await _pickAndSetGroupAvatar(store, conv);
                              if (url != null && url.isNotEmpty) {
                                setSheetState(() => avatarUrl = url);
                                setState(() {
                                  final idx = _chatConversations.indexWhere(
                                    (c) =>
                                        c.conversationKey ==
                                        conv.conversationKey,
                                  );
                                  if (idx >= 0) {
                                    _chatConversations[idx] = ChatConversation(
                                      conversationKey: conv.conversationKey,
                                      kind: conv.kind,
                                      title: conv.title,
                                      members: conv.members,
                                      avatarUrl: url,
                                    );
                                  }
                                });
                              }
                            }
                          : null,
                      child: () {
                        final effectiveUrl = avatarUrl;
                        return CircleAvatar(
                          radius: 36,
                          backgroundImage: (effectiveUrl != null &&
                                  effectiveUrl.isNotEmpty)
                              ? AvatarUrlResolver.imageProvider(effectiveUrl)
                              : null,
                          onBackgroundImageError: (_, __) {},
                          child: (effectiveUrl == null || effectiveUrl.isEmpty)
                              ? const Icon(Icons.camera_alt, size: 32)
                              : null,
                        );
                      }(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      conv.title.isNotEmpty
                          ? conv.title
                          : labels.defaultGroupName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (canManage) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final title = await _promptGroupTitle(
                                  conv.title.isNotEmpty
                                      ? conv.title
                                      : labels.defaultGroupName,
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
                                      SnackBar(
                                        content: Text(
                                          labels.genericError(error),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(labels.renameAction),
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
                                      SnackBar(
                                        content: Text(
                                          labels.groupDeletedLocally,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: Text(labels.delete),
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
                              trailing:
                                  canManage && profile != store.owner.value
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            setSheetState(
                                              () => members.remove(profile),
                                            );
                                            try {
                                              await store.repository.api
                                                  .removeGroupMember(
                                                actorProfile: store.owner.value,
                                                conversationKey:
                                                    conv.conversationKey,
                                                profile: profile,
                                              );
                                            } catch (_) {
                                              // silently ignored — non-critical operation
                                            }
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
                        title: Text(labels.addMember),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _addMemberToGroup(store, conv);
                        },
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

  Future<String?> _pickAndSetGroupAvatar(
    TaskStore store,
    ChatConversation conv,
  ) async {
    final labels = _groupChatLabels;
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return null;
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').lastOrNull ?? 'jpg';
      final uploadResult = await store.repository.api.chatUploadMedia(
        actorProfile: store.owner.value,
        bytes: bytes,
        filename: 'group_avatar.$ext',
      );
      final avatarUrl = uploadResult.assetUrl;
      if (avatarUrl.isEmpty) return null;

      // Persist locally: SharedPreferences + local DB
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('group_avatar_${conv.conversationKey}', avatarUrl);
      await store.repository.db.upsertConversation(
        ChatConversation(
          conversationKey: conv.conversationKey,
          kind: conv.kind,
          title: conv.title,
          members: conv.members,
          avatarUrl: avatarUrl,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.avatarUpdated)),
        );
      }
      return avatarUrl;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.avatarUploadFailed(error))),
        );
      }
      return null;
    }
  }

  Future<String?> _promptGroupTitle(String initial) async {
    if (!mounted) return null;
    final labels = _groupChatLabels;
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              labels.groupNameTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(
                hintText: labels.groupNameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(labels.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  child: Text(labels.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteGroup(ChatConversation conv) async {
    if (!mounted) return false;
    final labels = _groupChatLabels;
    final title = conv.title.isNotEmpty ? conv.title : labels.defaultGroupName;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(labels.deleteGroupTitle),
        content: Text(labels.deleteGroupMessage(title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(labels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(labels.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _addMemberToGroup(TaskStore store, ChatConversation conv) async {
    final labels = _groupChatLabels;
    final available = _chatContacts
        .where((c) => !conv.members.contains(c.profileKey))
        .toList();
    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.noAvailableContacts)),
        );
      }
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(labels.selectMember),
        children: available
            .map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c.profileKey),
                child: Text(contactLabel(c)),
              ),
            )
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
          SnackBar(content: Text(labels.memberAdded(_profileLabel(selected)))),
        );
      }
      await _refreshChatBootstrap(store);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(labels.genericError(error))),
        );
      }
    }
  }

  Future<void> _pickAndSendDocument(TaskStore store) async {
    final labels = _attachmentLabels;
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
            SnackBar(content: Text(labels.fileReadFailed)),
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
            SnackBar(content: Text(labels.fileTooLarge(maxMb: 50))),
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
          SnackBar(content: Text(labels.documentSendFailed(error))),
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
    final labels = _attachmentLabels;
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
          title: Text(labels.photoCaptionTitle),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: labels.captionHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(labels.skipCaption),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: Text(labels.done),
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
        attachments.add(
          ChatAttachment(
            kind: 'image',
            assetUrl: uploaded.assetUrl,
            imageMeta: uploaded.imageMeta,
            sortOrder: i,
          ),
        );
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
          SnackBar(content: Text(labels.photoSendFailed(error))),
        );
      }
    }
  }

  /// Update upload progress for an optimistic message
  void _updateUploadProgress(
    String conversationKey,
    String clientId,
    int index,
    int total,
    double progress,
  ) {
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
    String conversationKey,
    String clientId,
    List<ChatMessage> realMsgs,
  ) {
    final msgs = _chatMessagesByConversation[conversationKey];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.clientMessageId == clientId);
    msgs.addAll(realMsgs);
    _chatMessagesByConversation[conversationKey] = msgs;
  }

  /// Mark optimistic messages as failed (remove them)
  void _failOptimisticMessages(
    String conversationKey,
    String clientId,
    String error,
  ) {
    final msgs = _chatMessagesByConversation[conversationKey];
    if (msgs == null) return;
    msgs.removeWhere((m) => m.clientMessageId == clientId);
    _chatMessagesByConversation[conversationKey] = msgs;
    debugPrint('Upload failed ($clientId): $error');
    if (mounted) setState(() {});
  }

  Future<void> _pickAndSendVideo(TaskStore store) async {
    final labels = _attachmentLabels;
    final video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
    );
    if (video == null) return;

    // Check raw file size (before compression)
    try {
      final sizeBytes = await video.length();
      const maxRawBytes = 500 * 1024 * 1024; // 500 MB raw limit
      if (sizeBytes > maxRawBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                labels.videoTooLarge(
                  sizeMb: (sizeBytes / (1024 * 1024)).round(),
                  maxMb: 500,
                ),
              ),
            ),
          );
        }
        return;
      }
    } catch (e, st) {
      debugPrint('[attach] file size check error: $e\n$st');
      // silently ignored
    }

    // Optional caption
    String caption = '';
    if (mounted) {
      final captionCtl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(labels.videoCaptionTitle),
          content: TextField(
            controller: captionCtl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: labels.captionHint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(labels.skipCaption),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, captionCtl.text.trim()),
              child: Text(labels.done),
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
      // Phase 1: Compress video (0% → 25%)
      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.0);
      final compressStart = DateTime.now();

      // Simulate smooth progress during compression
      Timer? compressTimer;
      double simProgress = 0.0;
      compressTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
        simProgress += 0.01;
        if (simProgress > 0.24) simProgress = 0.24;
        _updateUploadProgress(conversationKey, clientId, 0, 1, simProgress);
      });

      final compressedFile = await _compressVideo(video.path, (_) {});
      compressTimer.cancel();
      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.25);

      final compressMs =
          DateTime.now().difference(compressStart).inMilliseconds;
      debugPrint(
        'Video compression took ${compressMs}ms, path: $compressedFile',
      );

      // Phase 2: Read compressed file (25% → 30%)
      final compressedMedia =
          compressedFile != null ? File(compressedFile) : File(video.path);

      // Simulate smooth progress during read
      double readProgress = 0.25;
      Timer? readTimer;
      readTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
        readProgress += 0.01;
        if (readProgress > 0.29) readProgress = 0.29;
        _updateUploadProgress(conversationKey, clientId, 0, 1, readProgress);
      });

      final bytes = await compressedMedia.readAsBytes();
      readTimer.cancel();
      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.30);

      // Phase 3: Upload with real network progress (30% → 98%)
      final uploaded = await api.chatUploadMedia(
        actorProfile: actor,
        bytes: bytes,
        filename: 'video_compressed.mp4',
        onProgress: (progress) {
          // progress 0..1 → mapped to 0.30..0.98 with 1% steps
          final p = 0.30 + (progress * 0.68);
          _updateUploadProgress(conversationKey, clientId, 0, 1, p);
        },
      );

      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.98);
      final meta = Map<String, dynamic>.from(uploaded.imageMeta);

      final attachment = ChatAttachment(
        kind: 'video',
        assetUrl: uploaded.assetUrl,
        imageMeta: meta,
        sortOrder: 0,
      );

      _updateUploadProgress(conversationKey, clientId, 0, 1, 0.96);

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
          SnackBar(content: Text(labels.videoSendFailed(error))),
        );
      }
    }
  }

  /// Compress video for messenger delivery.
  /// Returns path to compressed file, or null if compression failed/skipped.
  Future<String?> _compressVideo(
    String sourcePath,
    void Function(double) onProgress,
  ) async {
    try {
      final info = await VideoCompress.compressVideo(
        sourcePath,
        quality: VideoQuality.MediumQuality,
        includeAudio: true,
        deleteOrigin: false,
      );
      // video_compress doesn't support progress callback natively,
      // but we can simulate phases
      onProgress(0.5);
      if (info != null && info.path != null && info.path!.isNotEmpty) {
        onProgress(1.0);
        return info.path;
      }
    } catch (e) {
      debugPrint('[video] native compression error: $e');
      // compression not available on all platforms
    }
    // Fallback: compress using ffmpeg via VideoCompress if available
    try {
      final info = await VideoCompress.compressVideo(
        sourcePath,
        quality: VideoQuality.LowQuality,
        includeAudio: true,
        deleteOrigin: false,
      );
      onProgress(1.0);
      if (info != null && info.path != null && info.path!.isNotEmpty) {
        return info.path;
      }
    } catch (e) {
      debugPrint('[video] ffmpeg compression error: $e');
      // compression failed, will send original
    }
    onProgress(1.0);
    return null; // send original
  }

  Future<void> _openAttachMenu(TaskStore store) async {
    if (!mounted) return;
    final labels = _attachmentLabels;
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
                title: Text(labels.gallery),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendPhotos(
                    store,
                    source: ImageSource.gallery,
                    allowMultiple: true,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(labels.camera),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _sendPhotos(store, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: Text(labels.video),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendVideo(store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(labels.document),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pickAndSendDocument(store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: Text(labels.sticker),
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
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: StickerPickerSheet(
            packs: _chatStickerPacks,
            assetUrlResolver: _absoluteAssetUrl,
            onStickerSelected: (sticker) async {
              Navigator.of(sheetContext).pop();
              await _sendBuiltInSticker(store, sticker);
            },
          ),
        );
      },
    );
  }

  void _receiveIncomingCall(
    CallSession session,
    IncomingCallPushAction action,
  ) {
    if (!mounted) {
      _pendingIncomingCallSession = session;
      return;
    }

    final service = _callService;
    if (service != null &&
        service.state != CallState.idle &&
        service.state != CallState.ended) {
      if (service.sessionId == session.sessionId) {
        _handleIncomingCallOpenAction(session, action);
      }
      return;
    }

    setState(() {
      _activeCallSession = session;
      _activeCallState = CallState.ringing;
    });

    if (service == null) {
      _pendingIncomingCallSession = session;
      return;
    }
    service.notifyIncomingCall(session);
    _handleIncomingCallOpenAction(session, action);
  }

  void _handleIncomingCall(CallSession session) {
    if (!mounted) return;
    setState(() {
      _activeCallSession = session;
      _activeCallState = CallState.ringing;
    });
  }

  void _openActiveCallScreen() {
    final session = _activeCallSession ?? _callService?.currentSession;
    if (session == null) return;
    final isIncoming = session.callerProfile != _store?.owner.value;
    _openCallScreen(session: session, isIncoming: isIncoming);
  }

  void _handleIncomingCallOpenAction(
    CallSession session,
    IncomingCallPushAction action,
  ) {
    _openCallScreen(session: session, isIncoming: true);
    if (action != IncomingCallPushAction.accept) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = _callService;
      if (!mounted ||
          service == null ||
          service.sessionId != session.sessionId ||
          service.state != CallState.ringing) {
        return;
      }
      unawaited(
        service.acceptCall(
          session.sessionId,
          callType: session.callType,
        ),
      );
    });
  }

  void _openCallScreen({
    required CallSession session,
    required bool isIncoming,
  }) {
    if (!mounted || _callService == null || _callScreenOpen) return;
    _callScreenOpen = true;
    final actor = _store?.owner.value ?? '';
    final peerProfile = session.callerProfile == actor
        ? session.calleeProfile
        : session.callerProfile;
    final peerLabel = _profileLabel(peerProfile);
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          callService: _callService!,
          session: session,
          isIncoming: isIncoming,
          peerLabel: peerLabel,
          onCallFinished: () {
            _callScreenOpen = false;
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    )
        .whenComplete(() {
      _callScreenOpen = false;
    });
  }

  void _acceptActiveCallFromBanner() {
    final session = _activeCallSession;
    if (session == null || _callService == null) return;
    _openCallScreen(session: session, isIncoming: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = _callService;
      if (!mounted ||
          service == null ||
          service.sessionId != session.sessionId) {
        return;
      }
      unawaited(
        service.acceptCall(
          session.sessionId,
          callType: session.callType,
        ),
      );
    });
  }

  void _endActiveCallFromBanner() {
    final session = _activeCallSession;
    final service = _callService;
    if (session == null || service == null) return;
    if (_activeCallState == CallState.ringing &&
        session.calleeProfile == _store?.owner.value) {
      unawaited(service.rejectCall(session.sessionId));
    } else {
      unawaited(service.endCall());
    }
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
        members: const [],
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

    setState(() {
      _activeCallSession = session;
      _activeCallState = CallState.calling;
    });
    _openCallScreen(session: session, isIncoming: false);
  }

  void _openCodeWhaleWorkspaces() {
    if (!mounted) {
      return;
    }
    if (!_accessPolicy.canUseWorkspaces) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_miscLabels.noWorkspaceAccess)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CodeWhaleWorkspacesPage(),
      ),
    );
  }

  String contactLabel(ChatContact contact) {
    if (contact.displayName.trim().isNotEmpty) {
      return contact.displayName.trim();
    }
    return _profileLabel(contact.profileKey);
  }

  void _openAdminAccess() {
    final store = _store;
    if (store == null || !_accessPolicy.canManageWorkspaceAccess) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminAccessPage(
          api: store.repository.api,
          actorProfile: store.owner.value,
          actorPhone: _currentProfilePhone,
          accessPolicy: _accessPolicy,
          contacts: _allKnownContacts(store),
          contactLabel: contactLabel,
          projects: store.projects.value,
          loadProjects: () async {
            await store.refreshProjectsAndGroups();
            return store.projects.value;
          },
        ),
      ),
    );
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
          accessPolicy: _accessPolicy,
          avatarUrl: _currentProfileAvatarUrl,
          onAvatarChanged: (url) {
            setState(() => _currentProfileAvatarUrl = url);
          },
          onDisplayNameChanged: (name) {
            setState(() => _currentProfileDisplayName = name);
          },
          onOpenAdmin: _accessPolicy.canManageWorkspaceAccess
              ? () {
                  Navigator.of(context).pop();
                  _openAdminAccess();
                }
              : null,
        ),
      ),
    );
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
  }) async {
    // When a project is selected, show assignees from project groups
    // Otherwise, show all known contacts
    List<ChatContact> contacts;
    if (store.currentProjectId.value.isNotEmpty) {
      final members = store.currentProjectGroupMembers;
      contacts = members
          .map(
            (profile) => ChatContact(
              profileKey: profile,
              displayName: _profileLabel(profile),
              phone: '',
              conversationKey: '',
            ),
          )
          .toList();
      // Always include self
      if (!contacts.any((c) => c.profileKey == store.owner.value)) {
        contacts.insert(
          0,
          ChatContact(
            profileKey: store.owner.value,
            displayName: _profileLabel(store.owner.value),
            phone: '',
            conversationKey: '',
          ),
        );
      }
    } else {
      contacts = _allKnownContacts(store);
    }

    final agentPolicy = await _agentPolicyForEditor(store, existing);
    if (!mounted) {
      return;
    }
    await showTaskEditorSheet(
      context: context,
      store: store,
      knownContacts: contacts,
      contactLabel: contactLabel,
      dateKey: dateKey,
      existing: existing,
      agentPolicy: agentPolicy,
      actorPhone: _currentProfilePhone,
      onSaved: () => _safeSyncDelta(store, showErrors: true),
    );
  }

  Future<AgentRunPolicy> _agentPolicyForEditor(
    TaskStore store,
    TaskItem? existing,
  ) async {
    if (!_accessPolicy.canUseAi || !_accessPolicy.canUseWorkspaces) {
      return const AgentRunPolicy.unavailable();
    }
    final workspaceId = _workspaceIdForTaskEditor(store, existing);
    if (workspaceId.isEmpty) {
      return AgentRunPolicy(
        allowed: false,
        mode: '',
        modeLabel: '',
        plugins: const [],
        allowedCommands: const [],
        reason: _miscLabels.selectWorkspaceProjectReason,
      );
    }
    try {
      return await store.repository.api.requestAgentPolicy(
        actorProfile: store.owner.value,
        actorPhone: _currentProfilePhone,
        taskId: existing?.id ?? '',
        taskType: 'feature',
        workspaceId: workspaceId,
        requestedMode: 'executor',
      );
    } catch (e, st) {
      debugPrint('[home] agent policy error: $e\n$st');
      return const AgentRunPolicy.unavailable();
    }
  }

  Future<void> _handleTaskWorkflowMoved(
    TaskItem previous,
    TaskItem current,
  ) async {
    if (previous.workflowStatus == current.workflowStatus ||
        current.workflowStatus != WorkflowStatus.in_progress ||
        !_accessPolicy.canUseAi ||
        !_accessPolicy.canUseWorkspaces) {
      return;
    }
    final store = _store;
    if (store == null) {
      return;
    }
    final policy = await _agentPolicyForEditor(store, current);
    if (!policy.allowed) {
      return;
    }
    final service = _taskAgentAutomation ??= TaskAgentAutomationService(
      store: store,
      actorPhone: () => _currentProfilePhone,
      onLog: (message) => debugPrint('[task-agent-auto] $message'),
    );
    final started = await service.continueLatestForInProgressTask(
      task: current,
      policy: policy,
    );
    if (started) {
      await _safeSyncDelta(store, showErrors: false);
    }
  }

  String _workspaceIdForTaskEditor(TaskStore store, TaskItem? existing) {
    final workspaceIds = _accessPolicy.workspaces
        .map((item) => (item['workspace_id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final workspaceIdSet = workspaceIds.toSet();
    final candidates = [
      existing?.projectId.trim() ?? '',
      store.currentProjectId.value.trim(),
    ];
    for (final candidate in candidates) {
      if (workspaceIdSet.contains(candidate)) {
        return candidate;
      }
    }
    if (workspaceIds.isNotEmpty) {
      return workspaceIds.first;
    }
    return candidates.firstWhere(
      (candidate) => candidate.isNotEmpty,
      orElse: () => '',
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
    TaskStore store,
    TaskItem item,
    DateTime target,
  ) async {
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
      tooltip: _miscLabels.colorSchemeTooltip,
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
                final labels = _miscLabels;
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
                      tooltip: labels.profile,
                      icon: const Icon(Icons.person_outline),
                      onPressed: _openProfile,
                    ),
                    actions: [
                      if (_accessPolicy.canManageWorkspaceAccess)
                        IconButton(
                          tooltip: labels.administration,
                          icon: const Icon(
                            Icons.admin_panel_settings_outlined,
                          ),
                          onPressed: _openAdminAccess,
                        ),
                      _themeMenuButton(),
                      ValueListenableBuilder<bool>(
                        valueListenable: store.canUndo,
                        builder: (context, canUndo, _) {
                          return IconButton(
                            tooltip: labels.undoLastAction,
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
                                        SnackBar(
                                          content: Text(
                                            labels.lastActionUndone,
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
                        tooltip: labels.fcmDiagnostics,
                        icon: const Icon(Icons.bug_report_outlined),
                        onPressed: _showFcmDiagnosticsDialog,
                      ),
                      IconButton(
                        tooltip: labels.calendar,
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
                        tooltip: labels.sync,
                        icon: const Icon(Icons.sync),
                        onPressed: () async =>
                            _safeSyncFull(store, showErrors: true),
                      ),
                    ],
                  ),
                  body: ActiveCallOverlay(
                    session: _activeCallSession,
                    state: _activeCallState,
                    owner: owner,
                    profileLabel: _profileLabel,
                    onOpen: _openActiveCallScreen,
                    onAccept: _acceptActiveCallFromBanner,
                    onEnd: _endActiveCallFromBanner,
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ValueListenableBuilder<int>(
                            valueListenable: store.pageIndex,
                            builder: (context, page, ____) {
                              if (!_accessPolicy.canUseTaskManager) {
                                return buildMessengerPage(store, compact: true);
                              }
                              if (page == 0) {
                                return buildTasksPage(store);
                              }
                              if (page == 1) {
                                return buildCalendarPage(store);
                              }
                              return buildMessengerPage(store, compact: true);
                            },
                          ),
                  ),
                  floatingActionButton: buildFloatingActionButton(store),
                  bottomNavigationBar: buildNavigationBar(store),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openDayTasksScreen(
    TaskStore store,
    DateTime day,
    List<TaskItem> dayTasks,
  ) {
    store.setSelectedDate(day);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayTasksPage(
          day: day,
          tasks: dayTasks,
          labelFor: _profileLabel,
          onEdit: (task) async {
            Navigator.of(context).pop();
            _openTaskEditor(store, existing: task);
          },
          onDelete: (task) async {
            final navigator = Navigator.of(context);
            await store.delete(task);
            await _safeSyncDelta(store, showErrors: true);
            if (mounted) {
              navigator.pop();
            }
          },
          onAddForDate: (date) async {
            store.setSelectedDate(date);
            Navigator.of(context).pop();
            await _openTaskEditor(store);
          },
        ),
      ),
    );
  }

  void _showFcmDiagnosticsDialog() {
    final diagnostics = _pushHandler?.diagnostics;
    if (diagnostics == null) return;
    final labels = _miscLabels;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return ValueListenableBuilder<String>(
          valueListenable: diagnostics,
          builder: (context, text, _) {
            return AlertDialog(
              title: Text(labels.fcmDiagnostics),
              content: SingleChildScrollView(
                child: SelectableText(text),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    diagnostics.value = labels.fcmRefreshInProgress;
                    await _pushHandler?.refreshDiagnostics();
                  },
                  child: Text(labels.refresh),
                ),
                TextButton(
                  onPressed: () async {
                    diagnostics.value = labels.fcmResetInProgress;
                    await _pushHandler?.refreshDiagnostics(
                      forceResetToken: true,
                    );
                  },
                  child: Text(labels.resetToken),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(labels.close),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _chatRealtime?.stop();
    _callStateSub?.cancel();
    _callService?.dispose();
    _chatInputCtl.dispose();
    _pushHandler?.dispose();
    _syncLoops?.dispose();
    _taskAgentAutomation?.dispose();
    _voiceRecorder?.dispose();
    _projectChatAgentBridge?.dispose();
    _projectChatAgentRunner?.dispose();
    unawaited(_desktopProcessHostService?.stopAll());
    _desktopThemeService?.state.dispose();
    _store?.dispose();
    super.dispose();
  }
}
