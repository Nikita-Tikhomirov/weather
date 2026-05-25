part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Chat initialization extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _ChatInitExtension on _HomePageState {
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
        _setChatBootstrapState(
          contacts,
          bootstrap.conversations,
          bootstrap.stickerPacks,
        );
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
    _removeConversationState(key);
  }

  Future<void> _initChat(TaskStore store) async {
    final api = store.repository.api;
    final db = store.repository.db;
    final actor = store.owner.value;

    // If a push already routed to a conversation, preserve the key
    // so _initChat doesn't undo the navigation.
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

      // If a push already routed to a conversation that isn't in the
      // server conversation list (e.g. a fresh direct chat just created
      // by the incoming message), add it back so the messenger UI can
      // display it.
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
        _setChatLoading(false);
      }
    }
  }
}
