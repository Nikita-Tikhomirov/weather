part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Share-receiver extracted from _HomePageState.
// Handles content shared from other Android apps (text, images,
// video) and forwards it to a chat conversation.
// ───────────────────────────────────────────────────────────────

extension _ShareReceiverExtension on _HomePageState {
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
            } catch (e, st) {
              debugPrint('[share] image upload error: $e\n$st');
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
            } catch (e, st) {
              debugPrint('[share] video upload error: $e\n$st');
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
        _setActiveConversation(conversationKey);
        // Mark messages as read
        store.repository.api
            .chatMarkRead(
              actorProfile: store.owner.value,
              conversationKey: conversationKey,
            )
            .catchError((_) {});
        await _refreshConversation(store, conversationKey,
            useNetwork: true, quiet: true);
      } catch (e, st) {
        debugPrint('[share] share error: $e\n$st');
        // silently ignore share errors
      }
    });
    // Signal to Android that Flutter is ready to receive share data
    channel.invokeMethod('ready');
  }
}
