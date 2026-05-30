import '../contracts/call_api.dart';
import '../contracts/chat_api.dart';
import '../contracts/sync_api.dart';
import '../models/call_models.dart';
import '../models/chat_models.dart';
import '../models/chat_snapshots.dart';
import '../models/device_snapshots.dart';
import '../models/family_group.dart';
import '../models/pending_event.dart';
import '../models/sync_snapshots.dart';
import '../models/task_project.dart';

import 'call_api_client.dart';
import 'chat_api_client.dart';
import 'sync_api_client.dart';

// Re-export for backward compatibility — consumers that import
// api_client.dart still see these types.
export '../models/chat_snapshots.dart';
export '../models/device_snapshots.dart';
export '../models/sync_snapshots.dart';

/// Facade that delegates to the focused API clients.
///
/// This preserves backward compatibility for all existing imports of
/// [ApiClient] while the implementation is split across:
/// - [SyncApiClient] (sync + projects/family-groups)
/// - [ChatApiClient] (chat)
/// - [CallApiClient] (audio/video calls)
class ApiClient implements SyncApi, ChatApi, CallApi {
  ApiClient({required String baseUrl, required String apiKey})
      : _sync = SyncApiClient(baseUrl: baseUrl, apiKey: apiKey),
        _chat = ChatApiClient(baseUrl: baseUrl, apiKey: apiKey),
        _call = CallApiClient(baseUrl: baseUrl, apiKey: apiKey);

  final SyncApiClient _sync;
  final ChatApiClient _chat;
  final CallApiClient _call;

  /// Public getters for backward compatibility with code that reads
  /// [baseUrl] or [apiKey] directly from an [ApiClient] reference.
  String get baseUrl => _sync.baseUrl;
  String get apiKey => _sync.apiKey;

  // -- SyncApi -----------------------------------------------------------

  @override
  Future<void> push({
    required String actorProfile,
    required List<PendingEvent> events,
    String source = 'mobile',
  }) {
    return _sync.push(
      actorProfile: actorProfile,
      events: events,
      source: source,
    );
  }

  @override
  Future<PullSnapshot> pull({
    required String since,
    bool changesMode = false,
    String? cursor,
  }) {
    return _sync.pull(
      since: since,
      changesMode: changesMode,
      cursor: cursor,
    );
  }

  @override
  void setActorProfileForPull(String actorProfile) {
    _sync.setActorProfileForPull(actorProfile);
  }

  @override
  Future<DeviceTokenRegistration> registerDeviceToken({
    required String actorProfile,
    required String token,
    required String platform,
    required String appVersion,
    String? deviceId,
    String playServices = 'unknown',
    String tokenStatus = 'active',
    String lastError = '',
  }) {
    return _sync.registerDeviceToken(
      actorProfile: actorProfile,
      token: token,
      platform: platform,
      appVersion: appVersion,
      deviceId: deviceId,
      playServices: playServices,
      tokenStatus: tokenStatus,
      lastError: lastError,
    );
  }

  @override
  Future<void> reportDeviceStatus({
    required String actorProfile,
    required String platform,
    required String appVersion,
    required String tokenStatus,
    required String playServices,
    String? token,
    String? deviceId,
    String? lastError,
  }) {
    return _sync.reportDeviceStatus(
      actorProfile: actorProfile,
      platform: platform,
      appVersion: appVersion,
      tokenStatus: tokenStatus,
      playServices: playServices,
      token: token,
      deviceId: deviceId,
      lastError: lastError,
    );
  }

  @override
  Future<PushDeviceStatus> pushDeviceStatus({
    required String actorProfile,
  }) {
    return _sync.pushDeviceStatus(actorProfile: actorProfile);
  }

  @override
  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  }) {
    return _sync.unregisterDeviceToken(
      actorProfile: actorProfile,
      token: token,
    );
  }

  // -- ChatApi -----------------------------------------------------------

  @override
  Future<ChatBootstrapSnapshot> chatBootstrap({
    required String actorProfile,
  }) {
    return _chat.chatBootstrap(actorProfile: actorProfile);
  }

  @override
  Future<PhoneProfileSession> deviceStart({
    required String phone,
    required String deviceId,
    String displayName = '',
  }) {
    return _chat.deviceStart(
      phone: phone,
      deviceId: deviceId,
      displayName: displayName,
    );
  }

  @override
  Future<List<ChatContact>> resolveContacts({
    required String actorProfile,
    required List<String> phones,
  }) {
    return _chat.resolveContacts(
      actorProfile: actorProfile,
      phones: phones,
    );
  }

  @override
  Future<List<ChatContact>> familyMembers({
    required String actorProfile,
  }) {
    return _chat.familyMembers(actorProfile: actorProfile);
  }

  @override
  Future<List<ChatContact>> addFamilyMembers({
    required String actorProfile,
    required List<String> profiles,
  }) {
    return _chat.addFamilyMembers(
      actorProfile: actorProfile,
      profiles: profiles,
    );
  }

  @override
  Future<ChatMessagesSnapshot> chatFetchMessages({
    required String actorProfile,
    required String conversationKey,
    String? cursor,
    int limit = 50,
  }) {
    return _chat.chatFetchMessages(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<ChatMessage> chatSendMessage({
    required String actorProfile,
    required String conversationKey,
    required String messageType,
    String text = '',
    String? stickerId,
    String? imageUrl,
    Map<String, dynamic>? imageMeta,
    List<ChatAttachment> attachments = const [],
    String? clientMessageId,
  }) {
    return _chat.chatSendMessage(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      messageType: messageType,
      text: text,
      stickerId: stickerId,
      imageUrl: imageUrl,
      imageMeta: imageMeta,
      attachments: attachments,
      clientMessageId: clientMessageId,
    );
  }

  @override
  Future<ChatConversation> chatCreateGroup({
    required String actorProfile,
    required String title,
    required List<String> memberProfiles,
  }) {
    return _chat.chatCreateGroup(
      actorProfile: actorProfile,
      title: title,
      memberProfiles: memberProfiles,
    );
  }

  @override
  Future<ChatMessage> chatSetReaction({
    required String actorProfile,
    required String messageId,
    required String reaction,
  }) {
    return _chat.chatSetReaction(
      actorProfile: actorProfile,
      messageId: messageId,
      reaction: reaction,
    );
  }

  @override
  Future<ChatMessage> chatEditMessage({
    required String actorProfile,
    required String messageId,
    required String text,
  }) {
    return _chat.chatEditMessage(
      actorProfile: actorProfile,
      messageId: messageId,
      text: text,
    );
  }

  @override
  Future<ChatMessage> chatDeleteMessage({
    required String actorProfile,
    required String messageId,
  }) {
    return _chat.chatDeleteMessage(
      actorProfile: actorProfile,
      messageId: messageId,
    );
  }

  @override
  Future<ChatUploadResult> chatUploadSticker({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'sticker.png',
  }) {
    return _chat.chatUploadSticker(
      actorProfile: actorProfile,
      bytes: bytes,
      filename: filename,
    );
  }

  @override
  Future<ChatUploadResult> chatUploadMedia({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) {
    return _chat.chatUploadMedia(
      actorProfile: actorProfile,
      bytes: bytes,
      filename: filename,
      onProgress: onProgress,
    );
  }

  @override
  Future<ChatUploadResult> chatUploadDocument({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) {
    return _chat.chatUploadDocument(
      actorProfile: actorProfile,
      bytes: bytes,
      filename: filename,
      onProgress: onProgress,
    );
  }

  @override
  Future<String> uploadProfileAvatar({
    required String actorProfile,
    required List<int> bytes,
    String filename = 'avatar.jpg',
  }) {
    return _chat.uploadProfileAvatar(
      actorProfile: actorProfile,
      bytes: bytes,
      filename: filename,
    );
  }

  @override
  Future<void> addGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) {
    return _chat.addGroupMember(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      profile: profile,
    );
  }

  @override
  Future<void> removeGroupMember({
    required String actorProfile,
    required String conversationKey,
    required String profile,
  }) {
    return _chat.removeGroupMember(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      profile: profile,
    );
  }

  @override
  Future<void> renameGroup({
    required String actorProfile,
    required String conversationKey,
    required String title,
  }) {
    return _chat.renameGroup(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      title: title,
    );
  }

  @override
  Future<void> setGroupAvatar({
    required String actorProfile,
    required String conversationKey,
    required String avatarUrl,
  }) {
    return _chat.setGroupAvatar(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Future<void> deleteGroup({
    required String actorProfile,
    required String conversationKey,
  }) {
    return _chat.deleteGroup(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
    );
  }

  @override
  Future<void> chatSendTyping({
    required String actorProfile,
    required String conversationKey,
  }) {
    return _chat.chatSendTyping(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
    );
  }

  @override
  Future<void> chatMarkRead({
    required String actorProfile,
    required String conversationKey,
  }) {
    return _chat.chatMarkRead(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
    );
  }

  @override
  Future<List<StickerPack>> chatStickerPacks() {
    return _chat.chatStickerPacks();
  }

  // -- CallApi -----------------------------------------------------------

  @override
  Future<CallSession> callInitiate({
    required String actorProfile,
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  }) {
    return _call.callInitiate(
      actorProfile: actorProfile,
      conversationKey: conversationKey,
      callType: callType,
      calleeProfile: calleeProfile,
    );
  }

  @override
  Future<CallSession> callAccept({
    required String actorProfile,
    required String sessionId,
  }) {
    return _call.callAccept(
      actorProfile: actorProfile,
      sessionId: sessionId,
    );
  }

  @override
  Future<CallSession> callReject({
    required String actorProfile,
    required String sessionId,
  }) {
    return _call.callReject(
      actorProfile: actorProfile,
      sessionId: sessionId,
    );
  }

  @override
  Future<CallSession> callEnd({
    required String actorProfile,
    required String sessionId,
  }) {
    return _call.callEnd(
      actorProfile: actorProfile,
      sessionId: sessionId,
    );
  }

  @override
  Future<void> callSignal({
    required String actorProfile,
    required String sessionId,
    required String signalType,
    dynamic sdp,
    dynamic candidate,
  }) {
    return _call.callSignal(
      actorProfile: actorProfile,
      sessionId: sessionId,
      signalType: signalType,
      sdp: sdp,
      candidate: candidate,
    );
  }

  @override
  Future<CallSignalsPoll> callPollSignals({
    required String actorProfile,
    required String sessionId,
    String? cursor,
  }) {
    return _call.callPollSignals(
      actorProfile: actorProfile,
      sessionId: sessionId,
      cursor: cursor,
    );
  }

  @override
  Future<CallSession?> callCheckIncoming({
    required String actorProfile,
  }) {
    return _call.callCheckIncoming(actorProfile: actorProfile);
  }

  // -- Projects & Family Groups (delegated to SyncApiClient) -------------

  Future<List<TaskProject>> listProjects({
    required String actorProfile,
  }) {
    return _sync.listProjects(actorProfile: actorProfile);
  }

  Future<TaskProject> createProject({
    required String actorProfile,
    required String name,
    String description = '',
  }) {
    return _sync.createProject(
      actorProfile: actorProfile,
      name: name,
      description: description,
    );
  }

  Future<void> updateProject({
    required String actorProfile,
    required String id,
    required String name,
    String description = '',
    List<String>? groupIds,
  }) {
    return _sync.updateProject(
      actorProfile: actorProfile,
      id: id,
      name: name,
      description: description,
      groupIds: groupIds,
    );
  }

  Future<void> deleteProject({
    required String actorProfile,
    required String id,
  }) {
    return _sync.deleteProject(actorProfile: actorProfile, id: id);
  }

  Future<void> setProjectGroups({
    required String actorProfile,
    required String projectId,
    required List<String> groupIds,
  }) {
    return _sync.setProjectGroups(
      actorProfile: actorProfile,
      projectId: projectId,
      groupIds: groupIds,
    );
  }

  Future<List<FamilyGroup>> listFamilyGroups({
    required String actorProfile,
  }) {
    return _sync.listFamilyGroups(actorProfile: actorProfile);
  }

  Future<Map<String, List<String>>> listProjectGroupMap({
    required String actorProfile,
  }) {
    return _sync.listProjectGroupMap(actorProfile: actorProfile);
  }

  Future<FamilyGroup> createFamilyGroup({
    required String actorProfile,
    required String name,
    required List<String> members,
  }) {
    return _sync.createFamilyGroup(
      actorProfile: actorProfile,
      name: name,
      members: members,
    );
  }

  Future<void> updateFamilyGroup({
    required String actorProfile,
    required String id,
    required String name,
    List<String>? members,
  }) {
    return _sync.updateFamilyGroup(
      actorProfile: actorProfile,
      id: id,
      name: name,
      members: members,
    );
  }

  Future<void> deleteFamilyGroup({
    required String actorProfile,
    required String id,
  }) {
    return _sync.deleteFamilyGroup(actorProfile: actorProfile, id: id);
  }
}
