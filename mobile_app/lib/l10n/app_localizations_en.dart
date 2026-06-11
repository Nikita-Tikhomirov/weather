// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Family ToDo';

  @override
  String get tasksTab => 'Tasks';

  @override
  String get calendarTab => 'Calendar';

  @override
  String get chatsTab => 'Chats';

  @override
  String get messengerTab => 'Messenger';

  @override
  String get familyTab => 'Family';

  @override
  String get familyTasks => 'Family Tasks';

  @override
  String get dashboardOnDate => 'On date';

  @override
  String get dashboardDone => 'Done';

  @override
  String get dashboardFamily => 'Family';

  @override
  String get dashboardOverdue => 'Overdue';

  @override
  String get dashboardFamilyHint => 'Family';

  @override
  String get dashboardOverdueHint => 'Overdue';

  @override
  String get selectDate => 'Select date';

  @override
  String get upcomingTasks => 'Upcoming tasks';

  @override
  String get filterUpcoming => 'Upcoming';

  @override
  String get filterOverdue => 'Overdue';

  @override
  String get filterDone => 'Done';

  @override
  String get filterAll => 'All';

  @override
  String get noTasks => 'No tasks';

  @override
  String get noTasksForFilter => 'No tasks match this filter';

  @override
  String get noTasksForDate => 'No tasks for this date';

  @override
  String get close => 'Close';

  @override
  String get more => 'more';

  @override
  String get dropHere => 'Drop here';

  @override
  String get message => 'Message';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get send => 'Send';

  @override
  String get incomingVideoCall => 'Incoming video call';

  @override
  String get incomingAudioCall => 'Incoming audio call';

  @override
  String get ongoingVideoCall => 'Ongoing video call';

  @override
  String get ongoingAudioCall => 'Ongoing audio call';

  @override
  String get openCallScreen => 'Open call screen';

  @override
  String get open => 'Open';

  @override
  String get shareText => 'Share text';

  @override
  String get sharePhoto => 'Share photo';

  @override
  String get returnToCall => 'Return';

  @override
  String get calling => 'Calling...';

  @override
  String get incomingCall => 'Incoming call...';

  @override
  String get inCall => 'In call';

  @override
  String get callEnded => 'Call ended';

  @override
  String get decline => 'Decline';

  @override
  String get accept => 'Accept';

  @override
  String get endCall => 'End';

  @override
  String get microphone => 'Microphone';

  @override
  String get unmute => 'Unmute';

  @override
  String get speaker => 'Speaker';

  @override
  String get headset => 'Headset';

  @override
  String get search => 'Search';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get undo => 'Undo';

  @override
  String get syncAction => 'Sync';

  @override
  String get voice => 'Voice';

  @override
  String get today => 'Today';

  @override
  String get addTask => 'Add Task';

  @override
  String get newTask => 'New task';

  @override
  String get editTask => 'Edit task';

  @override
  String get taskSettingsTab => 'Settings';

  @override
  String get taskWorkTab => 'Work';

  @override
  String get taskAgentTab => 'Agent';

  @override
  String get taskTitle => 'Title';

  @override
  String get taskDetails => 'Details';

  @override
  String get chatTaskDraft => 'Task draft';

  @override
  String get taskSummary => 'Summary';

  @override
  String get checklist => 'Checklist';

  @override
  String get actionItems => 'Action items';

  @override
  String get decisions => 'Decisions';

  @override
  String get blockers => 'Blockers';

  @override
  String get sources => 'Sources';

  @override
  String get createTask => 'Create task';

  @override
  String get taskFromChat => 'Task from chat';

  @override
  String get taskProject => 'Project';

  @override
  String get taskGroup => 'Group';

  @override
  String get dueDate => 'Due date';

  @override
  String get time => 'Time';

  @override
  String get priority => 'Priority';

  @override
  String get taskStatus => 'Status';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get workflowTodo => 'To do';

  @override
  String get workflowInProgress => 'In progress';

  @override
  String get workflowInReview => 'In review';

  @override
  String get workflowDone => 'Done';

  @override
  String get workflowArchive => 'Archive';

  @override
  String get reminder => 'Reminder';

  @override
  String get taskReminders => 'Reminders';

  @override
  String get participants => 'Participants';

  @override
  String get taskAssignees => 'Assignees';

  @override
  String get taskDuration => 'Duration estimate (min)';

  @override
  String get selectProject => 'Select project';

  @override
  String get selectGroup => 'Select group';

  @override
  String get projectHasNoGroups => 'This project has no groups.';

  @override
  String get selectProjectGroup => 'Select a project group.';

  @override
  String get groupMembersMissing => 'No group members were found in contacts.';

  @override
  String get newProject => 'New project';

  @override
  String get editProject => 'Edit project';

  @override
  String get projectNameLabel => 'Project name';

  @override
  String get description => 'Description';

  @override
  String get groups => 'Groups';

  @override
  String get create => 'Create';

  @override
  String get projectNameRequired => 'Enter project name';

  @override
  String projectSaveFailed(Object error) {
    return 'Error: $error';
  }

  @override
  String get newGroup => 'New group';

  @override
  String get editGroup => 'Edit group';

  @override
  String get groupNameLabel => 'Group name';

  @override
  String get noContacts => 'No contacts. Add contacts in Messenger.';

  @override
  String get groupNameRequired => 'Enter group name';

  @override
  String get groupMemberRequired => 'Select at least one participant';

  @override
  String groupSaveFailed(Object error) {
    return 'Error: $error';
  }

  @override
  String get projectsSection => 'Projects';

  @override
  String get createProjectAction => 'Create project';

  @override
  String get createGroupAction => 'Create group';

  @override
  String get noProjectsYetAction => 'No projects yet. Press + to create one.';

  @override
  String get noGroupsYetAction => 'No groups yet. Press + to create one.';

  @override
  String get projectControlCreateProjectHint =>
      'Create a project to connect chat and agent.';

  @override
  String get projectControlChatsNotLinked => 'No linked chats';

  @override
  String projectControlChatsCount(int count) {
    return 'Chats: $count';
  }

  @override
  String get projectControlWorkspaceNotSelected => 'Workspace not selected';

  @override
  String projectControlWorkspaceChip(Object label) {
    return 'Workspace: $label';
  }

  @override
  String projectControlWorkspaceUnavailable(Object label) {
    return 'Workspace: $label (no access)';
  }

  @override
  String get projectControlNoAgentAccess => 'No agent access';

  @override
  String get projectControlWorkspaceLoading => 'Workspace is loading';

  @override
  String get projectControlAgentAvailable => 'Agent available';

  @override
  String get projectControlLinkedChats => 'Linked chats';

  @override
  String get projectControlAssignGroupForChat =>
      'Assign a group to the project to create a project chat.';

  @override
  String get projectControlCreateChat => 'Create project chat';

  @override
  String get projectControlRefreshChat => 'Refresh project chat';

  @override
  String get projectControlAnalyzeChat => 'Chat analysis';

  @override
  String get projectControlDraftTask => 'Task draft';

  @override
  String get projectControlStartAgent => 'Start agent';

  @override
  String get projectAgentMenu => 'Project agent';

  @override
  String get projectControlProjectStatus => 'Project status';

  @override
  String get workspaceBridgeNotLoaded => 'Workspace list has not loaded yet.';

  @override
  String get workspaceBridgeEmpty => 'CodeWhale returned no workspaces.';

  @override
  String workspaceBridgeLoaded(int count) {
    return 'Loaded workspaces: $count';
  }

  @override
  String get primaryWorkspace => 'Primary workspace';

  @override
  String get refreshWorkspaceList => 'Refresh workspaces';

  @override
  String get workspaceSearchHint => 'Search by name, id, or path';

  @override
  String workspaceFoundSummary(int found, int total, Object source) {
    return 'Found: $found of $total. Source: $source';
  }

  @override
  String get workspaceSourceBackendAccess => 'backend access';

  @override
  String get workspaceSourceCodeWhale => 'CodeWhale';

  @override
  String get clearWorkspaceBinding => 'Clear binding';

  @override
  String get projectAgentDisabledAfterClearing =>
      'The project agent will be disabled.';

  @override
  String get noWorkspacesFound => 'No workspaces found.';

  @override
  String get projectWorkspaceCleared => 'Project workspace cleared.';

  @override
  String get projectWorkspaceSaved => 'Project workspace saved.';

  @override
  String get projectWorkspaceSaveFailed => 'Could not save project workspace.';

  @override
  String projectChatReady(Object title) {
    return 'Project chat \"$title\" is ready.';
  }

  @override
  String projectChatCreateFailed(Object error) {
    return 'Could not create project chat: $error';
  }

  @override
  String get openProjectChatHint => 'Open the project chat.';

  @override
  String get selectWorkspace => 'Select workspace';

  @override
  String get changeWorkspace => 'Change workspace';

  @override
  String get workspaceNotSelectedSentence => 'Workspace not selected.';

  @override
  String workspaceSelected(Object label) {
    return 'Selected: $label.';
  }

  @override
  String workspaceControlAvailable(Object selectedText, int count) {
    return '$selectedText Available: $count.';
  }

  @override
  String get noAvailableWorkspacesToSelect =>
      'No available workspaces to select.';

  @override
  String get workspaceSettingLoading => 'Loading workspace setting...';

  @override
  String get refreshWorkspaces => 'Refresh workspaces';

  @override
  String get selectAction => 'Select';

  @override
  String projectGroupsSummary(Object groups) {
    return 'Groups: $groups';
  }

  @override
  String groupParticipantsSummary(Object participants) {
    return 'Participants: $participants';
  }

  @override
  String get deleteProjectTitle => 'Delete project?';

  @override
  String get deleteProjectMessage =>
      'The project and group links will be deleted.';

  @override
  String get deleteGroupTitle => 'Delete group?';

  @override
  String get deleteGroupMessage =>
      'The group will be removed from all projects.';

  @override
  String get connecting => 'Connecting...';

  @override
  String get reconnecting => 'Reconnecting...';

  @override
  String get connected => 'Connected';

  @override
  String get disconnected => 'Connection lost';

  @override
  String get connectionError => 'Connection error';

  @override
  String get retry => 'Retry';

  @override
  String get settings => 'Settings';

  @override
  String get profile => 'Profile';

  @override
  String get changePhoto => 'Change photo';

  @override
  String get name => 'Name';

  @override
  String get saveName => 'Save name';

  @override
  String get phone => 'Phone';

  @override
  String get phoneNumberLabel => 'Phone number';

  @override
  String get initialProfileTitle => 'Sign in with phone number';

  @override
  String get continueAction => 'Continue';

  @override
  String get administration => 'Administration';

  @override
  String get profileAdminSubtitle =>
      'Users, projects, workspaces, and agent roles';

  @override
  String get adminNoAccess => 'No administration access';

  @override
  String get adminBridgeNotConnected =>
      'CodeWhale workspaces are not connected';

  @override
  String get adminCodeWhaleDisabled => 'CodeWhale disabled';

  @override
  String get adminNewAccess => 'New access';

  @override
  String get adminContactFromContacts => 'Contact from contacts';

  @override
  String get adminContactsNotFound => 'No contacts found';

  @override
  String get adminWorkspace => 'Workspace';

  @override
  String get adminRole => 'Role';

  @override
  String get adminGrantAccess => 'Grant access';

  @override
  String get adminGrantedAccess => 'Granted access';

  @override
  String get adminNoActiveAccess => 'No active access yet';

  @override
  String get adminRevokeAccess => 'Revoke access';

  @override
  String get adminAgentRoles => 'Agent roles';

  @override
  String adminUsersCount(int count) {
    return 'Users: $count';
  }

  @override
  String adminWorkspacesCount(int count) {
    return 'Workspaces: $count';
  }

  @override
  String adminProjectsCount(int count) {
    return 'Projects: $count';
  }

  @override
  String get adminRoleWorkspaceUser => 'Workspace member';

  @override
  String get adminRoleWorkspaceUserDescription =>
      'Can view the workspace and use AI.';

  @override
  String get adminRoleAgentOperator => 'Agent operator';

  @override
  String get adminRoleAgentOperatorDescription =>
      'Can launch agent chats from tasks and run work in them.';

  @override
  String get adminRoleWorkspaceAdmin => 'Workspace administrator';

  @override
  String get adminRoleWorkspaceAdminDescription =>
      'Can manage access and advanced agent actions.';

  @override
  String avatarUploadFailed(Object error) {
    return 'Could not upload avatar: $error';
  }

  @override
  String get nameSaved => 'Name saved';

  @override
  String get theme => 'Theme';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get system => 'System';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Error';

  @override
  String get photo => 'Photo';

  @override
  String get file => 'File';

  @override
  String get sticker => 'Sticker';

  @override
  String get stickers => 'Stickers';

  @override
  String get noStickersLoaded => 'No stickers loaded yet';

  @override
  String get noSearchResults => 'No results found';

  @override
  String get allStyles => 'All styles';

  @override
  String get allTopics => 'All topics';

  @override
  String get voiceMessage => 'Voice message';

  @override
  String get typing => 'typing...';

  @override
  String get online => 'online';

  @override
  String get offline => 'offline';

  @override
  String get markRead => 'Mark read';

  @override
  String get reply => 'Reply';

  @override
  String get forward => 'Forward';

  @override
  String get copy => 'Copy';

  @override
  String get newSession => 'New session';

  @override
  String get workspaces => 'Workspaces';

  @override
  String get attachFolder => 'Attach folder';

  @override
  String get createWorkspace => 'Create workspace';

  @override
  String get noWorkspacesYet => 'No workspaces yet';

  @override
  String get back => 'Back';

  @override
  String get createSession => 'Create session';

  @override
  String get manageSession => 'Manage session';

  @override
  String get noSessionsYet => 'No sessions yet';

  @override
  String get running => 'Running';

  @override
  String get port => 'port';

  @override
  String get waitingToStart => 'Waiting to start';

  @override
  String get stopped => 'Stopped';

  @override
  String get killed => 'Killed';

  @override
  String get unknownStatus => 'Unknown status';

  @override
  String get folderSelection => 'Folder selection';

  @override
  String get refreshFolders => 'Refresh folders';

  @override
  String get currentFolder => 'Current folder';

  @override
  String get copyPath => 'Copy path';

  @override
  String get parentFolder => 'Parent folder';

  @override
  String get noFoldersHere => 'No folders here';

  @override
  String get connectThisFolder => 'Connect this folder';

  @override
  String get sessionHistoryEmpty => 'Session history is empty';

  @override
  String get attachPhoto => 'Attach photo';

  @override
  String get attachDocument => 'Attach document';

  @override
  String get copyText => 'Copy text';

  @override
  String get copied => 'Copied';

  @override
  String get workProgress => 'Work progress';

  @override
  String get stopGeneration => 'Stop generation';

  @override
  String get sessionTab => 'Session';

  @override
  String get filesTab => 'Files';

  @override
  String get commandsTab => 'Commands';

  @override
  String get sessionStatusLabel => 'Status';

  @override
  String get sessionPidLabel => 'PID';

  @override
  String get sessionPortLabel => 'Port';

  @override
  String get sessionEventsLabel => 'Events';

  @override
  String get noValue => 'none';

  @override
  String get sessionIdleStatus => 'Idle';

  @override
  String get sessionUnknownStatus => 'Unknown';

  @override
  String get restartWorker => 'Restart worker';

  @override
  String get stopSession => 'Stop session';

  @override
  String get killStuckSession => 'Kill stuck session';

  @override
  String get restartAction => 'Restart';

  @override
  String get stopAction => 'Stop';

  @override
  String get killAction => 'Kill';

  @override
  String get document => 'Document';

  @override
  String get projectRoot => 'Project root';

  @override
  String get upOneLevel => 'Up one level';

  @override
  String get refreshFiles => 'Refresh files';

  @override
  String get copyFileText => 'Copy file text';

  @override
  String get noFiles => 'No files';

  @override
  String get insertPathInChat => 'Insert path in chat';

  @override
  String get previewFile => 'Preview file';

  @override
  String projectFilesTitle(Object projectName) {
    return 'Files - $projectName';
  }

  @override
  String get loadingFiles => 'Loading files...';

  @override
  String get folderEmpty => 'Folder is empty';

  @override
  String get previewAction => 'Preview';

  @override
  String get linkToChat => 'Link to chat';

  @override
  String get sessionCodeWhaleModes => 'CodeWhale modes';

  @override
  String get provider => 'Provider';

  @override
  String get model => 'Model';

  @override
  String get approvalPolicy => 'Approval policy';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get defaultValue => 'default';

  @override
  String get autoModeTools => 'Tool auto mode';

  @override
  String get autoModeToolsTooltip => 'Run tools automatically';

  @override
  String get autoModeToolsSubtitle => 'Passes --auto to CodeWhale exec';

  @override
  String get codeWhaleCommandsLoading => 'CodeWhale commands are loading...';

  @override
  String get skills => 'Skills';

  @override
  String get runSelected => 'Run selected';

  @override
  String get chooseSkills => 'Choose one or more skills';

  @override
  String selectedSkillsCount(int count) {
    return 'Selected: $count';
  }

  @override
  String get diagnostics => 'Diagnostics';

  @override
  String get resetToken => 'Reset token';

  @override
  String get refresh => 'Refresh';

  @override
  String get notificationChannelName => 'Notifications';

  @override
  String get notificationChannelDesc =>
      'Push notifications for tasks and reminders';

  @override
  String get notificationNewMessage => 'New message';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get ok => 'OK';
}
