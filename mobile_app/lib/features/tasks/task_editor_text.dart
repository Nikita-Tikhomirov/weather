import 'package:flutter/material.dart';

import '../../domain/task_domain_service.dart';
import '../../l10n/app_localizations.dart';

class TaskEditorText {
  const TaskEditorText(this.l10n);

  const TaskEditorText.fallback() : l10n = null;

  factory TaskEditorText.of(BuildContext context) {
    return TaskEditorText(AppLocalizations.of(context));
  }

  final AppLocalizations? l10n;

  String get newTask => l10n?.newTask ?? 'New task';
  String get editTask => l10n?.editTask ?? 'Edit task';
  String get settingsTab => l10n?.taskSettingsTab ?? 'Settings';
  String get workTab => l10n?.taskWorkTab ?? 'Work';
  String get agentTab => l10n?.taskAgentTab ?? 'Agent';
  String get agent => l10n?.taskAgent ?? 'Agent';
  String get user => l10n?.taskUserFallback ?? 'User';
  String get agentAccessGranted =>
      l10n?.taskAgentAccessGranted ?? 'Access granted';
  String get agentNoAccess => l10n?.taskAgentNoAccess ?? 'No access';
  String get agentQuestions => l10n?.taskAgentQuestions ?? 'Agent questions';
  String get agentLoadingChats =>
      l10n?.taskAgentLoadingChats ?? 'Loading chats';
  String get agentConnectChat => l10n?.taskAgentConnectChat ?? 'Connect chat';
  String get selectAgentChat =>
      l10n?.taskSelectAgentChat ?? 'Select agent chat';
  String get selectAgentWorkspace =>
      l10n?.taskSelectAgentWorkspace ?? 'Select workspace for agent chat';
  String get agentNewChat => l10n?.taskAgentNewChat ?? 'New chat';
  String get agentChat => l10n?.taskAgentChat ?? 'Agent chat';
  String agentSessionTitle(String title) =>
      l10n?.taskAgentSessionTitle(title) ?? 'Agent: $title';
  String get agentTaskChats => l10n?.taskAgentTaskChats ?? 'Task chats';
  String get agentNoChats =>
      l10n?.taskAgentNoChats ?? 'No agent chats connected';
  String get noAgentChatsInWorkspace =>
      l10n?.taskNoAgentChatsInWorkspace ?? 'No agent chats in this workspace';
  String get agentChatNotLinkedToWorkspace =>
      l10n?.taskAgentChatNotLinkedToWorkspace ??
      'Agent chat is not linked to a workspace';
  String get agentConnectNoAccess =>
      l10n?.taskAgentConnectNoAccess ?? 'No permission to connect chat';
  String get connectedAgentChatTitle =>
      l10n?.taskConnectedAgentChatTitle ?? 'Connected agent chat';
  String get agentChatConnectedToCard =>
      l10n?.taskAgentChatConnectedToCard ??
      'Agent chat connected to the task card';
  String agentChatConnectFailed(Object error) =>
      l10n?.taskAgentChatConnectFailed(error) ??
      'Could not connect chat: $error';
  String get agentLaunchStarted =>
      l10n?.taskAgentLaunchStarted ?? 'New agent chat is starting';
  String agentQueueLaunchStarted(int count) =>
      l10n?.taskAgentQueueLaunchStarted(count) ??
      'Agent is starting the queue: $count tools';
  String get agentStartNoAccess =>
      l10n?.taskAgentStartNoAccess ?? 'No permission to start agent';
  String agentStartFailed(Object error) =>
      l10n?.taskAgentStartFailed(error) ?? 'Could not start agent: $error';
  String get agentQueueRunning =>
      l10n?.taskAgentQueueRunning ?? 'Queue running';
  String get workspace => l10n?.taskWorkspace ?? 'Workspace';
  String get workspaceField => l10n?.taskWorkspaceField ?? 'Workspace';
  String get workspaceNotSelected =>
      l10n?.taskWorkspaceNotSelected ?? 'Not selected';
  String get workspaceListNotLoaded =>
      l10n?.taskWorkspaceListNotLoaded ??
      'CodeWhale workspace list is not loaded';
  String get launchMode => l10n?.taskLaunchMode ?? 'Launch mode';
  String get launchAuto => l10n?.taskLaunchAuto ?? 'Auto';
  String get launchManual => l10n?.taskLaunchManual ?? 'Manual';
  String get agentProvider => l10n?.taskAgentProvider ?? 'Provider';
  String get agentModel => l10n?.taskAgentModel ?? 'Model';
  String get defaultValue => l10n?.defaultValue ?? 'default';
  String get agentConfirmations =>
      l10n?.taskAgentConfirmations ?? 'Confirmations';
  String get agentToolAutoMode =>
      l10n?.taskAgentToolAutoMode ?? 'Tool auto mode';
  String get agentTools => l10n?.taskAgentTools ?? 'Tools';
  String get agentToolsLoading =>
      l10n?.taskAgentToolsLoading ?? 'Tool list is loading';
  String get agentToolsNotLoaded =>
      l10n?.taskAgentToolsNotLoaded ?? 'CodeWhale tools are not loaded';
  String get codeWhaleUnavailable =>
      l10n?.taskCodeWhaleUnavailable ?? 'CodeWhale is unavailable';
  String agentToolsLoadFailed(Object error) =>
      l10n?.taskAgentToolsLoadFailed(error) ??
      'Could not load agent tools: $error';
  String agentWorkspacesLoadFailed(Object error) =>
      l10n?.taskAgentWorkspacesLoadFailed(error) ??
      'Could not load workspaces: $error';
  String get continueAction => l10n?.continueAction ?? 'Continue';
  String get continueWork => l10n?.taskContinueWork ?? 'Continue work';
  String get saveTaskFirst => l10n?.taskSaveTaskFirst ?? 'Save the task first';
  String saveError(String error) {
    switch (error) {
      case TaskValidationError.titleRequired:
      case 'Укажите название задачи.':
        return l10n?.taskSaveTitleRequired ?? 'Enter a task title';
      case TaskValidationError.projectRequired:
      case 'Выберите проект.':
        return selectProject;
      case TaskValidationError.projectGroupRequired:
      case 'Выберите группу проекта.':
        return selectProjectGroup;
      case TaskValidationError.projectGroupNotFound:
      case 'Выбранная группа не входит в проект.':
        return l10n?.taskSaveGroupNotInProject ??
            'Selected group is not in the project.';
      case TaskValidationError.projectGroupForbidden:
      case 'Нет прав на создание задачи в этой группе.':
        return l10n?.taskSaveGroupCreateNoAccess ??
            'No permission to create a task in this group.';
      case TaskValidationError.assigneesOutsideGroup:
      case 'Ответственные должны входить в выбранную группу.':
        return l10n?.taskSaveAssigneesOutsideGroup ??
            'Assignees must belong to the selected group.';
      case TaskValidationError.invalidStatus:
      case 'Некорректный статус задачи.':
        return l10n?.taskSaveInvalidStatus ?? 'Invalid task status.';
      case TaskValidationError.invalidPriority:
      case 'Некорректный приоритет задачи.':
        return l10n?.taskSaveInvalidPriority ?? 'Invalid task priority.';
      case TaskValidationError.invalidReminders:
      case 'Некорректные интервалы напоминаний.':
        return l10n?.taskSaveInvalidReminders ?? 'Invalid reminder intervals.';
      case TaskValidationError.genericFailure:
      case 'Невозможно сохранить задачу.':
        return l10n?.taskSaveGenericFailure ?? 'Could not save task.';
    }
    return error;
  }

  String get agentContinueNoAccess =>
      l10n?.taskAgentContinueNoAccess ?? 'No permission to continue agent';
  String get agentContinuesFreshCard =>
      l10n?.taskAgentContinuesFreshCard ??
      'Agent continues with the fresh task card';
  String agentContinueFailed(Object error) =>
      l10n?.taskAgentContinueFailed(error) ??
      'Could not continue agent: $error';
  String get activityAgentSessionRequested =>
      l10n?.taskActivityAgentSessionRequested ?? 'requested a new agent chat';
  String get activityAgentSessionStartFailed =>
      l10n?.taskActivityAgentSessionStartFailed ?? 'could not start agent chat';
  String get activityAgentSessionResumed =>
      l10n?.taskActivityAgentSessionResumed ?? 'continued agent chat';
  String get activityAgentSessionResumeFailed =>
      l10n?.taskActivityAgentSessionResumeFailed ??
      'could not continue agent chat';
  String get activityAgentSessionError =>
      l10n?.taskActivityAgentSessionError ?? 'received an agent chat error';
  String get activityAgentSessionLinked =>
      l10n?.taskActivityAgentSessionLinked ?? 'linked agent chat';
  String get activityAgentExistingSessionLinked =>
      l10n?.taskActivityAgentExistingSessionLinked ??
      'linked existing agent chat';
  String activityAgentAutoMovedToStatus(Object status) =>
      l10n?.taskActivityAgentAutoMovedToStatus(status) ??
      'automatically moved card to $status';
  String get activityAgentQueueWaitingReview =>
      l10n?.taskActivityAgentQueueWaitingReview ?? 'waiting for card review';
  String get activityAgentQueueCompleted =>
      l10n?.taskActivityAgentQueueCompleted ?? 'completed agent queue';
  String get activityAgentQueueNeedsMoreWork =>
      l10n?.taskActivityAgentQueueNeedsMoreWork ?? 'waiting for more changes';
  String activityAgentStatusChanged(Object status) =>
      l10n?.taskActivityAgentStatusChanged(status) ?? 'moved card to $status';
  String get activityAgentCardUpdated =>
      l10n?.taskActivityAgentCardUpdated ?? 'updated task card';
  String get agentPlanTitle => l10n?.taskAgentPlanTitle ?? 'Agent plan';
  String agentQueueStepFailed(Object status) =>
      l10n?.taskAgentQueueStepFailed(status) ??
      'One of the agent steps did not complete: $status';
  String get agentQueueTaskCardUnavailable =>
      l10n?.taskAgentQueueTaskCardUnavailable ??
      'family-task-card is unavailable. Agent queue stopped.';
  String get codeWhaleError =>
      l10n?.codeWhaleErrorFallback ?? 'CodeWhale error';
  String get agentStatusPending => l10n?.waitingToStart ?? 'Waiting to start';
  String get agentStatusLinked => l10n?.connected ?? 'Connected';
  String get agentStatusRunning => l10n?.running ?? 'Running';
  String get agentStatusDone => l10n?.done ?? 'Done';
  String get sessionStatusIdle => l10n?.sessionIdleStatus ?? 'Idle';
  String get sessionStatusRunning => l10n?.running ?? 'Running';
  String get sessionStatusStopped => l10n?.stopped ?? 'Stopped';
  String get sessionStatusKilled => l10n?.killed ?? 'Killed';
  String get sessionStatusError => l10n?.error ?? 'Error';
  String get sessionStatusUnknown => l10n?.sessionUnknownStatus ?? 'Unknown';
  String get agentQuestionBlocksWork =>
      l10n?.taskAgentQuestionBlocksWork ?? 'Blocks work';
  String get agentSkills => l10n?.taskAgentSkills ?? 'Skills';
  String get agentCommands => l10n?.taskAgentCommands ?? 'Commands';
  String agentAvailableCount(int count) =>
      l10n?.taskAgentAvailableCount(count) ?? 'Available: $count';
  String get agentQueue => l10n?.taskAgentQueue ?? 'Execution queue';
  String get agentQueueHint =>
      l10n?.taskAgentQueueHint ?? 'Select tools; the work step will run last';
  String get moveUp => l10n?.taskMoveUp ?? 'Up';
  String get moveDown => l10n?.taskMoveDown ?? 'Down';
  String get agentTaskCardStep => l10n?.taskAgentTaskCardStep ?? 'Task card';
  String get agentTaskCardReadStep =>
      l10n?.taskAgentTaskCardReadStep ?? 'Read task card';
  String get agentAppContextStep =>
      l10n?.taskAgentAppContextStep ?? 'App context';
  String get workStep => l10n?.taskWorkStep ?? 'Task work';
  String get workStepSubtitle =>
      l10n?.taskWorkStepSubtitle ??
      'Checklists, comments, and task files are required';
  String get refresh => l10n?.refresh ?? 'Refresh';
  String get save => l10n?.save ?? 'Save';
  String get title => l10n?.taskTitle ?? 'Title';
  String get project => l10n?.taskProject ?? 'Project';
  String get group => l10n?.taskGroup ?? 'Group';
  String get selectProject => l10n?.selectProject ?? 'Select project';
  String get selectGroup => l10n?.selectGroup ?? 'Select group';
  String get projectHasNoGroups =>
      l10n?.projectHasNoGroups ?? 'This project has no groups.';
  String get priority => l10n?.priority ?? 'Priority';
  String get status => l10n?.taskStatus ?? 'Status';
  String get low => l10n?.low ?? 'Low';
  String get medium => l10n?.medium ?? 'Medium';
  String get high => l10n?.high ?? 'High';
  String get workflowTodo => l10n?.workflowTodo ?? 'To do';
  String get workflowInProgress => l10n?.workflowInProgress ?? 'In progress';
  String get workflowInReview => l10n?.workflowInReview ?? 'In review';
  String get workflowDone => l10n?.workflowDone ?? 'Done';
  String get workflowArchive => l10n?.workflowArchive ?? 'Archive';
  String get assignees => l10n?.taskAssignees ?? 'Assignees';
  String get selectProjectGroup =>
      l10n?.selectProjectGroup ?? 'Select a project group.';
  String get groupMembersMissing =>
      l10n?.groupMembersMissing ?? 'No group members were found in contacts.';
  String get reminders => l10n?.taskReminders ?? 'Reminders';
  String reminderLabel(int minutes) {
    switch (minutes) {
      case 1440:
        return l10n?.taskReminderBefore24Hours ?? '24 hours before';
      case 720:
        return l10n?.taskReminderBefore12Hours ?? '12 hours before';
      case 180:
        return l10n?.taskReminderBefore3Hours ?? '3 hours before';
      case 120:
        return l10n?.taskReminderBefore2Hours ?? '2 hours before';
      case 60:
        return l10n?.taskReminderBefore1Hour ?? '1 hour before';
      case 30:
        return l10n?.taskReminderBefore30Minutes ?? '30 minutes before';
      case 15:
        return l10n?.taskReminderBefore15Minutes ?? '15 minutes before';
      case 5:
        return l10n?.taskReminderBefore5Minutes ?? '5 minutes before';
    }
    return '$minutes min';
  }

  String get duration => l10n?.taskDuration ?? 'Duration estimate (min)';
  String get details => l10n?.taskDetails ?? 'Details';
  String get comments => l10n?.taskComments ?? 'Comments';
  String get commentOrCaption =>
      l10n?.taskCommentComposerHint ?? 'Comment or caption';
  String get commentActions => l10n?.taskCommentActions ?? 'Comment actions';
  String get replyToComment => l10n?.taskReplyToComment ?? 'Reply to comment';
  String get editingComment => l10n?.taskEditingComment ?? 'Editing comment';
  String get commentDeleted => l10n?.taskCommentDeleted ?? 'Comment deleted';
  String get commentFallback => l10n?.taskCommentFallback ?? 'Comment';
  String get activityCommentEdited =>
      l10n?.taskActivityCommentEdited ?? 'edited a comment';
  String get activityCommentAdded =>
      l10n?.taskActivityCommentAdded ?? 'added a comment';
  String get activityCommentAddedWithAttachment =>
      l10n?.taskActivityCommentAddedWithAttachment ??
      'added a comment with an attachment';
  String get activityCommentReplied =>
      l10n?.taskActivityCommentReplied ?? 'replied to a comment';
  String get activityCommentDeleted =>
      l10n?.taskActivityCommentDeleted ?? 'deleted a comment';
  String activityChecklistAdded(Object title) =>
      l10n?.taskActivityChecklistAdded(title) ?? 'created checklist "$title"';
  String activityChecklistItemAdded(Object item) =>
      l10n?.taskActivityChecklistItemAdded(item) ?? 'added item "$item"';
  String get activityChecklistItemDone =>
      l10n?.taskActivityChecklistItemDone ?? 'completed checklist item';
  String get activityChecklistItemReopened =>
      l10n?.taskActivityChecklistItemReopened ?? 'reopened checklist item';
  String activityChecklistRenamed(Object title) =>
      l10n?.taskActivityChecklistRenamed(title) ??
      'renamed checklist to "$title"';
  String activityChecklistDeleted(Object title) =>
      l10n?.taskActivityChecklistDeleted(title) ?? 'deleted checklist "$title"';
  String get activityChecklistItemRenamed =>
      l10n?.taskActivityChecklistItemRenamed ?? 'edited checklist item';
  String get activityChecklistItemDeleted =>
      l10n?.taskActivityChecklistItemDeleted ?? 'deleted checklist item';
  String get deleteCommentTitle =>
      l10n?.taskDeleteCommentTitle ?? 'Delete comment?';
  String get deleteCommentMessage =>
      l10n?.taskDeleteCommentMessage ??
      'The comment will be removed from the task card.';
  String get cancelCommentAction => l10n?.taskCancelCommentAction ?? 'Cancel';
  String get edited => l10n?.edited ?? 'edited';
  String get photo => l10n?.photo ?? 'Photo';
  String get file => l10n?.file ?? 'File';
  String get send => l10n?.send ?? 'Send';
  String get attachment => l10n?.attachment ?? 'Attachment';
  String get openPhotoAttachment =>
      l10n?.taskOpenPhotoAttachment ?? 'Open photo';
  String get openFileAttachment => l10n?.taskOpenFileAttachment ?? 'Open file';
  String get removeAttachment =>
      l10n?.taskRemoveAttachment ?? 'Remove attachment';
  String get photoCaptionTitle =>
      l10n?.taskPhotoCaptionTitle ?? 'Photo caption';
  String get fileCaptionTitle => l10n?.taskFileCaptionTitle ?? 'File caption';
  String get attachmentCaptionHint =>
      l10n?.taskAttachmentCaptionHint ?? 'Add caption (optional)';
  String get skipAttachmentCaption => l10n?.taskSkipAttachmentCaption ?? 'Skip';
  String attachmentUploadFailed(Object error) =>
      l10n?.taskAttachmentUploadFailed(error) ??
      'Could not upload attachment: $error';
  String get attachmentEmptyOrCorrupt =>
      l10n?.taskAttachmentEmptyOrCorrupt ?? 'The file is empty or corrupted.';
  String get attachmentUploadMissingUrl =>
      l10n?.taskAttachmentUploadMissingUrl ??
      'The server did not return a file URL.';
  String get fileReadFailed =>
      l10n?.taskFileReadFailed ?? 'Could not read file';
  String get fileOpenFailed =>
      l10n?.taskFileOpenFailed ?? 'Could not open file';
  String get reply => l10n?.reply ?? 'Reply';
  String get edit => l10n?.edit ?? 'Edit';
  String get delete => l10n?.delete ?? 'Delete';
  String get cancel => l10n?.cancel ?? 'Cancel';
  String get done => l10n?.done ?? 'Done';
  String get noComments => l10n?.taskNoComments ?? 'No comments';
  String get checklists => l10n?.taskChecklists ?? 'Checklists';
  String get newChecklist => l10n?.taskNewChecklist ?? 'New checklist';
  String get addChecklist => l10n?.taskAddChecklist ?? 'Add checklist';
  String get noChecklists => l10n?.taskNoChecklists ?? 'No checklists';
  String get editChecklist => l10n?.taskEditChecklist ?? 'Edit checklist';
  String get checklistName => l10n?.taskChecklistName ?? 'Checklist name';
  String get deleteChecklist => l10n?.taskDeleteChecklist ?? 'Delete checklist';
  String get deleteChecklistTitle =>
      l10n?.taskDeleteChecklistTitle ?? 'Delete checklist?';
  String get deleteChecklistMessage =>
      l10n?.taskDeleteChecklistMessage ??
      'The checklist and its items will be removed from the task.';
  String get editChecklistItem => l10n?.taskEditChecklistItem ?? 'Edit item';
  String get checklistItemText => l10n?.taskChecklistItemText ?? 'Item text';
  String get deleteChecklistItem =>
      l10n?.taskDeleteChecklistItem ?? 'Delete item';
  String get deleteChecklistItemTitle =>
      l10n?.taskDeleteChecklistItemTitle ?? 'Delete item?';
  String get deleteChecklistItemMessage =>
      l10n?.taskDeleteChecklistItemMessage ??
      'The item will be removed from the checklist.';
  String get checklistItem => l10n?.taskChecklistItem ?? 'Item';
  String get addChecklistItem => l10n?.taskAddChecklistItem ?? 'Add item';
  String get activity => l10n?.taskActivity ?? 'Activity';
  String get activityEmpty => l10n?.taskActivityEmpty ?? 'Nothing yet';
}
