import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/features/tasks/task_editor_text.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fallback matches English labels for harnesses without l10n',
      (tester) async {
    const text = TaskEditorText.fallback();
    late TaskEditorText localized;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localized = TaskEditorText.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.newTask, localized.newTask);
    expect(text.settingsTab, localized.settingsTab);
    expect(text.title, localized.title);
    expect(text.agent, localized.agent);
    expect(text.user, localized.user);
    expect(text.openPhotoAttachment, localized.openPhotoAttachment);
    expect(text.openFileAttachment, localized.openFileAttachment);
    expect(text.removeAttachment, localized.removeAttachment);
    expect(text.fileReadFailed, localized.fileReadFailed);
    expect(text.fileOpenFailed, localized.fileOpenFailed);
    expect(text.selectAgentWorkspace, localized.selectAgentWorkspace);
    expect(text.noAgentChatsInWorkspace, localized.noAgentChatsInWorkspace);
    expect(
      text.agentSessionTitle('Forms'),
      localized.agentSessionTitle('Forms'),
    );
    expect(
      text.agentChatNotLinkedToWorkspace,
      localized.agentChatNotLinkedToWorkspace,
    );
    expect(text.agentConnectNoAccess, localized.agentConnectNoAccess);
    expect(text.connectedAgentChatTitle, localized.connectedAgentChatTitle);
    expect(text.agentChatConnectedToCard, localized.agentChatConnectedToCard);
    expect(
      text.agentChatConnectFailed('network'),
      localized.agentChatConnectFailed('network'),
    );
    expect(text.agentLaunchStarted, localized.agentLaunchStarted);
    expect(
      text.agentQueueLaunchStarted(2),
      localized.agentQueueLaunchStarted(2),
    );
    expect(text.agentStartNoAccess, localized.agentStartNoAccess);
    expect(
      text.agentStartFailed('network'),
      localized.agentStartFailed('network'),
    );
    expect(text.agentContinueNoAccess, localized.agentContinueNoAccess);
    expect(text.agentContinuesFreshCard, localized.agentContinuesFreshCard);
    expect(
      text.agentContinueFailed('network'),
      localized.agentContinueFailed('network'),
    );
    expect(
      text.activityAgentSessionRequested,
      localized.activityAgentSessionRequested,
    );
    expect(
      text.activityAgentSessionStartFailed,
      localized.activityAgentSessionStartFailed,
    );
    expect(
      text.activityAgentSessionResumed,
      localized.activityAgentSessionResumed,
    );
    expect(
      text.activityAgentSessionResumeFailed,
      localized.activityAgentSessionResumeFailed,
    );
    expect(text.activityAgentSessionError, localized.activityAgentSessionError);
    expect(
      text.activityAgentSessionLinked,
      localized.activityAgentSessionLinked,
    );
    expect(
      text.activityAgentExistingSessionLinked,
      localized.activityAgentExistingSessionLinked,
    );
    expect(
      text.activityAgentAutoMovedToStatus('In review'),
      localized.activityAgentAutoMovedToStatus('In review'),
    );
    expect(
      text.activityAgentQueueWaitingReview,
      localized.activityAgentQueueWaitingReview,
    );
    expect(
      text.activityAgentQueueCompleted,
      localized.activityAgentQueueCompleted,
    );
    expect(
      text.activityAgentQueueNeedsMoreWork,
      localized.activityAgentQueueNeedsMoreWork,
    );
    expect(
      text.activityAgentStatusChanged('Done'),
      localized.activityAgentStatusChanged('Done'),
    );
    expect(text.activityAgentCardUpdated, localized.activityAgentCardUpdated);
    expect(text.agentPlanTitle, localized.agentPlanTitle);
    expect(
      text.agentQueueStepFailed('failed'),
      localized.agentQueueStepFailed('failed'),
    );
    expect(
      text.agentQueueTaskCardUnavailable,
      localized.agentQueueTaskCardUnavailable,
    );
    expect(text.agentTaskCardStep, localized.agentTaskCardStep);
    expect(text.agentTaskCardReadStep, localized.agentTaskCardReadStep);
    expect(text.agentAppContextStep, localized.agentAppContextStep);
    expect(text.workStep, localized.workStep);
    expect(text.codeWhaleError, localized.codeWhaleError);
    expect(text.activityCommentEdited, localized.activityCommentEdited);
    expect(text.activityCommentAdded, localized.activityCommentAdded);
    expect(
      text.activityCommentAddedWithAttachment,
      localized.activityCommentAddedWithAttachment,
    );
    expect(text.activityCommentReplied, localized.activityCommentReplied);
    expect(text.activityCommentDeleted, localized.activityCommentDeleted);
    expect(
      text.activityChecklistAdded('Launch'),
      localized.activityChecklistAdded('Launch'),
    );
    expect(
      text.activityChecklistItemAdded('Build'),
      localized.activityChecklistItemAdded('Build'),
    );
    expect(
      text.activityChecklistItemDone,
      localized.activityChecklistItemDone,
    );
    expect(
      text.activityChecklistItemReopened,
      localized.activityChecklistItemReopened,
    );
    expect(
      text.activityChecklistRenamed('Release'),
      localized.activityChecklistRenamed('Release'),
    );
    expect(
      text.activityChecklistDeleted('Release'),
      localized.activityChecklistDeleted('Release'),
    );
    expect(
      text.activityChecklistItemRenamed,
      localized.activityChecklistItemRenamed,
    );
    expect(
      text.activityChecklistItemDeleted,
      localized.activityChecklistItemDeleted,
    );
    expect(
      text.saveError('Укажите название задачи.'),
      localized.saveError('Укажите название задачи.'),
    );
    expect(
      text.saveError(TaskValidationError.titleRequired),
      localized.saveError(TaskValidationError.titleRequired),
    );
    expect(
      text.saveError('Выберите проект.'),
      localized.saveError('Выберите проект.'),
    );
    expect(
      text.saveError('Unknown failure'),
      localized.saveError('Unknown failure'),
    );
    expect(text.codeWhaleUnavailable, localized.codeWhaleUnavailable);
    expect(
      text.agentToolsLoadFailed('network'),
      localized.agentToolsLoadFailed('network'),
    );
    expect(
      text.agentWorkspacesLoadFailed('network'),
      localized.agentWorkspacesLoadFailed('network'),
    );
  });

  testWidgets('reads English labels from AppLocalizations', (tester) async {
    late TaskEditorText text;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            text = TaskEditorText.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.newTask, 'New task');
    expect(text.settingsTab, 'Settings');
    expect(text.title, 'Title');
    expect(text.selectProject, 'Select project');
    expect(text.agent, 'Agent');
    expect(text.agentTaskCardStep, 'Task card');
    expect(text.agentTaskCardReadStep, 'Read task card');
    expect(text.agentAppContextStep, 'App context');
    expect(text.workStep, 'Task work');
    expect(text.user, 'User');
    expect(text.openPhotoAttachment, 'Open photo');
    expect(text.openFileAttachment, 'Open file');
    expect(text.removeAttachment, 'Remove attachment');
    expect(
      text.attachmentUploadFailed('network'),
      'Could not upload attachment: network',
    );
    expect(text.attachmentEmptyOrCorrupt, 'The file is empty or corrupted.');
    expect(
      text.attachmentUploadMissingUrl,
      'The server did not return a file URL.',
    );
    expect(text.fileReadFailed, 'Could not read file');
    expect(text.fileOpenFailed, 'Could not open file');
    expect(text.selectAgentWorkspace, 'Select workspace for agent chat');
    expect(
      text.noAgentChatsInWorkspace,
      'No agent chats in this workspace',
    );
    expect(text.agentSessionTitle('Forms'), 'Agent: Forms');
    expect(
      text.agentChatNotLinkedToWorkspace,
      'Agent chat is not linked to a workspace',
    );
    expect(text.agentConnectNoAccess, 'No permission to connect chat');
    expect(text.connectedAgentChatTitle, 'Connected agent chat');
    expect(
      text.agentChatConnectedToCard,
      'Agent chat connected to the task card',
    );
    expect(
      text.agentChatConnectFailed('network'),
      'Could not connect chat: network',
    );
    expect(text.agentLaunchStarted, 'New agent chat is starting');
    expect(
      text.agentQueueLaunchStarted(2),
      'Agent is starting the queue: 2 tools',
    );
    expect(text.agentStartNoAccess, 'No permission to start agent');
    expect(
      text.agentStartFailed('network'),
      'Could not start agent: network',
    );
    expect(text.agentContinueNoAccess, 'No permission to continue agent');
    expect(
      text.agentContinuesFreshCard,
      'Agent continues with the fresh task card',
    );
    expect(
      text.agentContinueFailed('network'),
      'Could not continue agent: network',
    );
    expect(
      text.activityAgentSessionRequested,
      'requested a new agent chat',
    );
    expect(
      text.activityAgentSessionStartFailed,
      'could not start agent chat',
    );
    expect(text.activityAgentSessionResumed, 'continued agent chat');
    expect(
      text.activityAgentSessionResumeFailed,
      'could not continue agent chat',
    );
    expect(text.activityAgentSessionError, 'received an agent chat error');
    expect(text.activityAgentSessionLinked, 'linked agent chat');
    expect(
      text.activityAgentExistingSessionLinked,
      'linked existing agent chat',
    );
    expect(
      text.activityAgentAutoMovedToStatus('In review'),
      'automatically moved card to In review',
    );
    expect(text.activityAgentQueueWaitingReview, 'waiting for card review');
    expect(text.activityAgentQueueCompleted, 'completed agent queue');
    expect(text.activityAgentQueueNeedsMoreWork, 'waiting for more changes');
    expect(
      text.activityAgentStatusChanged('Done'),
      'moved card to Done',
    );
    expect(text.activityAgentCardUpdated, 'updated task card');
    expect(text.agentPlanTitle, 'Agent plan');
    expect(
      text.agentQueueStepFailed('failed'),
      'One of the agent steps did not complete: failed',
    );
    expect(
      text.agentQueueTaskCardUnavailable,
      'family-task-card is unavailable. Agent queue stopped.',
    );
    expect(text.codeWhaleError, 'CodeWhale error');
    expect(text.activityCommentEdited, 'edited a comment');
    expect(text.activityCommentAdded, 'added a comment');
    expect(
      text.activityCommentAddedWithAttachment,
      'added a comment with an attachment',
    );
    expect(text.activityCommentReplied, 'replied to a comment');
    expect(text.activityCommentDeleted, 'deleted a comment');
    expect(text.activityChecklistAdded('Launch'), 'created checklist "Launch"');
    expect(text.activityChecklistItemAdded('Build'), 'added item "Build"');
    expect(text.activityChecklistItemDone, 'completed checklist item');
    expect(text.activityChecklistItemReopened, 'reopened checklist item');
    expect(
      text.activityChecklistRenamed('Release'),
      'renamed checklist to "Release"',
    );
    expect(
      text.activityChecklistDeleted('Release'),
      'deleted checklist "Release"',
    );
    expect(text.activityChecklistItemRenamed, 'edited checklist item');
    expect(text.activityChecklistItemDeleted, 'deleted checklist item');
    expect(text.saveError('Укажите название задачи.'), 'Enter a task title');
    expect(
      text.saveError(TaskValidationError.titleRequired),
      'Enter a task title',
    );
    expect(text.saveError('Выберите проект.'), 'Select project');
    expect(
      text.saveError('Неизвестная ошибка'),
      'Неизвестная ошибка',
    );
    expect(text.codeWhaleUnavailable, 'CodeWhale is unavailable');
    expect(
      text.agentToolsLoadFailed('network'),
      'Could not load agent tools: network',
    );
    expect(
      text.agentWorkspacesLoadFailed('network'),
      'Could not load workspaces: network',
    );
  });
}
