import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/chat_models.dart';
import '../../services/api_client.dart';
import '../../services/chat_realtime_service.dart';
import '../../services/local_db.dart';
import '../../state/task_store.dart';

/// Standalone chat-initialization helper extracted from _HomePageState.
///
/// Manages chat bootstrap, contact loading, realtime service lifecycle,
/// and conversation state. All dependencies injected via constructor
/// or callbacks — no access to widget state.
class HomeChatInitializer {
  HomeChatInitializer({
    required this.api,
    required this.db,
    required this.owner,
    this.onChatLoading,
    this.onActiveConversation,
    this.onChatInitState,
    this.onChatBootstrapState,
    this.onRemoveConversationState,
    this.onReplaceCallService,
    this.onRefreshConversation,
    this.onSaveAvatarUrls,
    this.onLoadProfileAvatars,
    this.onLoadPhoneContacts,
    this.onRefreshBootstrap,
    this.getActiveConversationKey,
    this.getPushAlreadyRouted,
    this.getIsProjectConversation,
  });

  final ApiClient api;
  final LocalDb db;
  final String owner;

  // ── Callbacks ──────────────────────────────────────────────────

  final void Function(bool loading)? onChatLoading;
  final void Function(String key)? onActiveConversation;
  final void Function(List<ChatContact> contacts,
      List<ChatConversation> convs, List<StickerPack> packs,
      bool clearConversation)? onChatInitState;
  final void Function(List<ChatContact> contacts,
      List<ChatConversation> convs, List<StickerPack> packs)? onChatBootstrapState;
  final void Function(String key)? onRemoveConversationState;
  final void Function(ApiClient api, String actorProfile)? onReplaceCallService;
  final Future<void> Function(String key,
      {required bool useNetwork, required bool quiet})? onRefreshConversation;
  final Future<void> Function(List<ChatContact> contacts)? onSaveAvatarUrls;
  final Future<void> Function(List<String> profileKeys)? onLoadProfileAvatars;
  final Future<void> Function(TaskStore store)? onLoadPhoneContacts;
  final Future<void> Function(TaskStore store)? onRefreshBootstrap;
  final String Function()? getActiveConversationKey;
  final bool Function()? getPushAlreadyRouted;
  final bool Function(String conversationKey)? getIsProjectConversation;

  // ── State ──────────────────────────────────────────────────────

  List<ChatContact> chatContacts = [];
  List<ChatContact> phoneContacts = [];
  List<ChatContact> familyMembers = [];
  final Map<String, String> profileAvatarUrls = {};
  final Map<String, List<ChatMessage>> chatMessagesByConversation = {};
  final Map<String, String> chatOlderCursors = {};
  final Map<String, bool> chatOlderLoading = {};
  final Map<String, bool> chatOlderExhausted = {};
  ChatRealtimeService? chatRealtime;

  // ── Public API ─────────────────────────────────────────────────

  /// Refresh chat contacts and conversations from the server
  /// without resetting the full chat state.
  Future<void> refreshChatBootstrap(TaskStore store) async {
    try {
      final bootstrap = await store.repository.api.chatBootstrap(
        actorProfile: store.owner.value,
      );
      await store.repository.db.replaceConversations(bootstrap.conversations);
      await store.repository.db.replaceStickerPacks(bootstrap.stickerPacks);

      await restoreLocalGroupAvatars(store, bootstrap.conversations);

      final mergedConversations =
          await store.repository.db.readConversations();

      final contacts = bootstrap.contacts;
      await onSaveAvatarUrls?.call(contacts);
      await onLoadProfileAvatars?.call([
        ...contacts.map((item) => item.profileKey),
        ...mergedConversations.expand((item) => item.members),
      ]);
      onChatBootstrapState?.call(
        contacts,
        mergedConversations,
        bootstrap.stickerPacks,
      );
    } catch (e, st) {
      debugPrint('[chat] bootstrap refresh error: $e\n$st');
    }
  }

  Future<void> refreshMessengerContacts(TaskStore store) async {
    await refreshChatBootstrap(store);
    await onLoadPhoneContacts?.call(store);
  }

  Future<void> restoreLocalGroupAvatars(
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

  Future<void> removeLocalConversation(
    TaskStore store,
    String conversationKey,
  ) async {
    final key = conversationKey.trim();
    if (key.isEmpty) return;
    await store.repository.db.deleteConversation(key);
    onRemoveConversationState?.call(key);
  }

  /// Full chat initialisation — called once on startup.
  Future<void> initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    final pushAlreadyRouted = getPushAlreadyRouted?.call() ?? false;
    final pushConversationKey =
        pushAlreadyRouted ? (getActiveConversationKey?.call() ?? '') : '';

    onChatLoading?.call(true);
    chatMessagesByConversation.clear();
    chatOlderCursors.clear();
    chatOlderLoading.clear();
    chatOlderExhausted.clear();
    if (!pushAlreadyRouted) {
      onActiveConversation?.call('');
    }

    try {
      final bootstrap = await api.chatBootstrap(actorProfile: actor);
      await db.replaceConversations(bootstrap.conversations);
      await db.replaceStickerPacks(bootstrap.stickerPacks);

      await restoreLocalGroupAvatars(store, bootstrap.conversations);

      final conversations = await db.readConversations();
      final stickerPacks = await db.readStickerPacks();

      await onSaveAvatarUrls?.call(bootstrap.contacts);
      await onLoadProfileAvatars?.call([
        ...bootstrap.contacts.map((item) => item.profileKey),
        ...conversations.expand((item) => item.members),
      ]);

      List<ChatConversation> finalConversations = conversations;
      if (pushConversationKey.isNotEmpty &&
          !finalConversations
              .any((c) => c.conversationKey == pushConversationKey) &&
          !(getIsProjectConversation?.call(pushConversationKey) ?? false)) {
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

      onChatInitState?.call(
        bootstrap.contacts,
        finalConversations,
        stickerPacks,
        !pushAlreadyRouted,
      );

      await onLoadPhoneContacts?.call(store);
      await chatRealtime?.stop();
      chatRealtime = ChatRealtimeService(
        api: api,
        actorProfile: actor,
        activeConversationKey: getActiveConversationKey ?? () => '',
        shouldPoll: () =>
            store.pageIndex.value == 4 &&
            !(getIsProjectConversation
                    ?.call(getActiveConversationKey?.call() ?? '') ??
                false),
        onMessagesUpdated: (conversationKey) async {
          await onRefreshConversation?.call(
            conversationKey,
            useNetwork: true,
            quiet: true,
          );
        },
      )..start();

      onReplaceCallService?.call(api, actor);

      if (pushConversationKey.isNotEmpty) {
        await onRefreshConversation?.call(
          pushConversationKey,
          useNetwork: true,
          quiet: true,
        );
      }

      // Load locally cached avatars
      final prefs = await SharedPreferences.getInstance();
      for (final contact in [...chatContacts, ...familyMembers]) {
        if (profileAvatarUrls.containsKey(contact.profileKey)) continue;
        final avatar = prefs.getString('avatar_${contact.profileKey}');
        if (avatar != null && avatar.isNotEmpty) {
          profileAvatarUrls[contact.profileKey] = avatar;
        }
      }
    } catch (error) {
      debugPrint('[chat] init error: $error');
    } finally {
      onChatLoading?.call(false);
    }
  }
}
