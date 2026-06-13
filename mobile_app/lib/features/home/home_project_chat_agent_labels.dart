import '../../l10n/app_localizations.dart';

class HomeProjectChatAgentLabels {
  const HomeProjectChatAgentLabels(this.l10n);

  final AppLocalizations? l10n;

  String get draftButtonUserMessage =>
      l10n?.homeProjectChatAgentDraftButtonUserMessage ??
      'User pressed the task draft button.';
  String get analyzingChat =>
      l10n?.homeProjectChatAgentAnalyzing ?? 'Tudushker is analyzing the chat.';
  String get unstructuredResponseSnack =>
      l10n?.homeProjectChatAgentUnstructuredResponse ??
      'Tudushker returned an unstructured response.';
  String get analyzeFailed =>
      l10n?.homeProjectChatAgentAnalyzeFailed ??
      'Could not analyze the project chat.';
  String get selectProjectWorkspace =>
      l10n?.homeProjectChatAgentSelectWorkspace ??
      'Select the project workspace in Project Control Center.';
  String get agentStarting =>
      l10n?.homeProjectChatAgentStarting ??
      'Project agent is starting in CodeWhale.';
  String get agentStartFailed =>
      l10n?.homeProjectChatAgentStartFailed ??
      'Could not start the project agent.';
  String get unstructuredResponseMessage =>
      l10n?.homeProjectChatAgentUnstructuredResponseMessage ??
      'I received an unstructured model response and did not send it to the '
          'chat. Try making the request a little more specific.';
  String get requestFailedMessage =>
      l10n?.homeProjectChatAgentRequestFailedMessage ??
      'I could not process the request. Check the project workspace and '
          'CodeWhale availability.';
  String get taskDraftMissingMessage =>
      l10n?.homeProjectChatAgentTaskDraftMissingMessage ??
      'I understood that a task card is needed, but could not build a '
          'structured draft.';
  String get agentSessionStartedMessage =>
      l10n?.homeProjectChatAgentSessionStartedMessage ??
      'Started a work session in the project workspace.';
  String get emptyReplyMessage =>
      l10n?.homeProjectChatAgentEmptyReplyMessage ??
      'I checked the context, but could not formulate a useful response.';
  String get aiUnavailableReplyMessage =>
      l10n?.homeProjectChatAgentAiUnavailableReplyMessage ??
      'I did not receive an AI response, so I will not invent an answer from '
          'chat fragments. Check CodeWhale and the project workspace, then '
          'try again.';
  String get aiUnavailableTaskDraftMessage =>
      l10n?.homeProjectChatAgentAiUnavailableTaskDraftMessage ??
      'I could not build a proper draft: I did not receive an AI response. I '
          'will not create a card from chat fragments. Check CodeWhale and '
          'the project workspace, then try again.';
  String get codeWhaleErrorFallback =>
      l10n?.codeWhaleErrorFallback ?? 'CodeWhale error';
  String get codeWhaleUnavailable =>
      l10n?.homeProjectChatAgentCodeWhaleUnavailable ??
      'CodeWhale is unavailable';
  String get defaultAgentTitle =>
      l10n?.homeProjectChatAgentDefaultTitle ?? 'Tudushker';
  String get imageSavedToGallery =>
      l10n?.homeImageSavedToGallery ?? 'Photo saved to gallery';
  String get imageSaveFailed =>
      l10n?.homeImageSaveFailed ?? 'Could not save photo';

  String agentTitle(String projectName) {
    return l10n?.homeProjectChatAgentTitle(projectName) ??
        'Tudushker: $projectName';
  }

  String taskCreatedInProject(String projectName) {
    return l10n?.homeProjectChatAgentTaskCreated(projectName) ??
        'Task created in project $projectName.';
  }

  String ownerFallbackMessage(String message) {
    return l10n?.homeProjectChatAgentOwnerFallbackMessage(message) ??
        'Tudushker: $message';
  }
}
