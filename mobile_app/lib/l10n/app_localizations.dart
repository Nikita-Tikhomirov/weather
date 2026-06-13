import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Family ToDo'**
  String get appTitle;

  /// No description provided for @tasksTab.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasksTab;

  /// No description provided for @calendarTab.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarTab;

  /// No description provided for @chatsTab.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsTab;

  /// No description provided for @messengerTab.
  ///
  /// In en, this message translates to:
  /// **'Messenger'**
  String get messengerTab;

  /// No description provided for @familyTab.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyTab;

  /// No description provided for @familyTasks.
  ///
  /// In en, this message translates to:
  /// **'Family Tasks'**
  String get familyTasks;

  /// No description provided for @dashboardOnDate.
  ///
  /// In en, this message translates to:
  /// **'On date'**
  String get dashboardOnDate;

  /// No description provided for @dashboardDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get dashboardDone;

  /// No description provided for @dashboardFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get dashboardFamily;

  /// No description provided for @dashboardOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get dashboardOverdue;

  /// No description provided for @dashboardFamilyHint.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get dashboardFamilyHint;

  /// No description provided for @dashboardOverdueHint.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get dashboardOverdueHint;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @upcomingTasks.
  ///
  /// In en, this message translates to:
  /// **'Upcoming tasks'**
  String get upcomingTasks;

  /// No description provided for @filterUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get filterUpcoming;

  /// No description provided for @filterOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get filterOverdue;

  /// No description provided for @filterDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get filterDone;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get noTasks;

  /// No description provided for @noTasksForFilter.
  ///
  /// In en, this message translates to:
  /// **'No tasks match this filter'**
  String get noTasksForFilter;

  /// No description provided for @noTasksForDate.
  ///
  /// In en, this message translates to:
  /// **'No tasks for this date'**
  String get noTasksForDate;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get more;

  /// No description provided for @dropHere.
  ///
  /// In en, this message translates to:
  /// **'Drop here'**
  String get dropHere;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @imageMessage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageMessage;

  /// No description provided for @audioMessage.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audioMessage;

  /// No description provided for @uploadPhasePreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get uploadPhasePreparing;

  /// No description provided for @uploadPhaseCompressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing...'**
  String get uploadPhaseCompressing;

  /// No description provided for @uploadPhaseReading.
  ///
  /// In en, this message translates to:
  /// **'Reading...'**
  String get uploadPhaseReading;

  /// No description provided for @uploadPhaseUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get uploadPhaseUploading;

  /// No description provided for @uploadPhaseSending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get uploadPhaseSending;

  /// No description provided for @uploadPhaseFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing...'**
  String get uploadPhaseFinishing;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @editMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessage;

  /// No description provided for @replyPreview.
  ///
  /// In en, this message translates to:
  /// **'Reply: {message}'**
  String replyPreview(String message);

  /// No description provided for @editingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get editingMessage;

  /// No description provided for @incomingVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming video call'**
  String get incomingVideoCall;

  /// No description provided for @incomingAudioCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming audio call'**
  String get incomingAudioCall;

  /// No description provided for @videoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get videoCall;

  /// No description provided for @audioCall.
  ///
  /// In en, this message translates to:
  /// **'Audio call'**
  String get audioCall;

  /// No description provided for @ongoingVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Ongoing video call'**
  String get ongoingVideoCall;

  /// No description provided for @ongoingAudioCall.
  ///
  /// In en, this message translates to:
  /// **'Ongoing audio call'**
  String get ongoingAudioCall;

  /// No description provided for @openCallScreen.
  ///
  /// In en, this message translates to:
  /// **'Open call screen'**
  String get openCallScreen;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @shareText.
  ///
  /// In en, this message translates to:
  /// **'Share text'**
  String get shareText;

  /// No description provided for @sharePhoto.
  ///
  /// In en, this message translates to:
  /// **'Share photo'**
  String get sharePhoto;

  /// No description provided for @returnToCall.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnToCall;

  /// No description provided for @calling.
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get calling;

  /// No description provided for @incomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming call...'**
  String get incomingCall;

  /// No description provided for @inCall.
  ///
  /// In en, this message translates to:
  /// **'In call'**
  String get inCall;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @endCall.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endCall;

  /// No description provided for @microphone.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get microphone;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @headset.
  ///
  /// In en, this message translates to:
  /// **'Headset'**
  String get headset;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get edited;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @syncAction.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncAction;

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @playVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Play voice message'**
  String get playVoiceMessage;

  /// No description provided for @pauseVoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Pause voice message'**
  String get pauseVoiceMessage;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add Task'**
  String get addTask;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @taskSettingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get taskSettingsTab;

  /// No description provided for @taskWorkTab.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get taskWorkTab;

  /// No description provided for @taskAgentTab.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get taskAgentTab;

  /// No description provided for @taskAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get taskAgent;

  /// No description provided for @taskUserFallback.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get taskUserFallback;

  /// No description provided for @taskAgentAccessGranted.
  ///
  /// In en, this message translates to:
  /// **'Access granted'**
  String get taskAgentAccessGranted;

  /// No description provided for @taskAgentNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No access'**
  String get taskAgentNoAccess;

  /// No description provided for @taskAgentQuestions.
  ///
  /// In en, this message translates to:
  /// **'Agent questions'**
  String get taskAgentQuestions;

  /// No description provided for @taskAgentLoadingChats.
  ///
  /// In en, this message translates to:
  /// **'Loading chats'**
  String get taskAgentLoadingChats;

  /// No description provided for @taskAgentConnectChat.
  ///
  /// In en, this message translates to:
  /// **'Connect chat'**
  String get taskAgentConnectChat;

  /// No description provided for @taskSelectAgentChat.
  ///
  /// In en, this message translates to:
  /// **'Select agent chat'**
  String get taskSelectAgentChat;

  /// No description provided for @taskSelectAgentWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Select workspace for agent chat'**
  String get taskSelectAgentWorkspace;

  /// No description provided for @taskAgentNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get taskAgentNewChat;

  /// No description provided for @taskAgentChat.
  ///
  /// In en, this message translates to:
  /// **'Agent chat'**
  String get taskAgentChat;

  /// No description provided for @taskAgentSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent: {title}'**
  String taskAgentSessionTitle(String title);

  /// No description provided for @taskAgentTaskChats.
  ///
  /// In en, this message translates to:
  /// **'Task chats'**
  String get taskAgentTaskChats;

  /// No description provided for @taskAgentNoChats.
  ///
  /// In en, this message translates to:
  /// **'No agent chats connected'**
  String get taskAgentNoChats;

  /// No description provided for @taskNoAgentChatsInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'No agent chats in this workspace'**
  String get taskNoAgentChatsInWorkspace;

  /// No description provided for @taskAgentChatNotLinkedToWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Agent chat is not linked to a workspace'**
  String get taskAgentChatNotLinkedToWorkspace;

  /// No description provided for @taskAgentConnectNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No permission to connect chat'**
  String get taskAgentConnectNoAccess;

  /// No description provided for @taskConnectedAgentChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected agent chat'**
  String get taskConnectedAgentChatTitle;

  /// No description provided for @taskAgentChatConnectedToCard.
  ///
  /// In en, this message translates to:
  /// **'Agent chat connected to the task card'**
  String get taskAgentChatConnectedToCard;

  /// No description provided for @taskAgentChatConnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect chat: {error}'**
  String taskAgentChatConnectFailed(Object error);

  /// No description provided for @taskAgentLaunchStarted.
  ///
  /// In en, this message translates to:
  /// **'New agent chat is starting'**
  String get taskAgentLaunchStarted;

  /// No description provided for @taskAgentQueueLaunchStarted.
  ///
  /// In en, this message translates to:
  /// **'Agent is starting the queue: {count} tools'**
  String taskAgentQueueLaunchStarted(int count);

  /// No description provided for @taskAgentStartNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No permission to start agent'**
  String get taskAgentStartNoAccess;

  /// No description provided for @taskAgentStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start agent: {error}'**
  String taskAgentStartFailed(Object error);

  /// No description provided for @taskAgentQueueRunning.
  ///
  /// In en, this message translates to:
  /// **'Queue running'**
  String get taskAgentQueueRunning;

  /// No description provided for @taskAgentQuestionBlocksWork.
  ///
  /// In en, this message translates to:
  /// **'Blocks work'**
  String get taskAgentQuestionBlocksWork;

  /// No description provided for @taskWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get taskWorkspace;

  /// No description provided for @taskWorkspaceField.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get taskWorkspaceField;

  /// No description provided for @taskWorkspaceNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get taskWorkspaceNotSelected;

  /// No description provided for @taskWorkspaceListNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale workspace list is not loaded'**
  String get taskWorkspaceListNotLoaded;

  /// No description provided for @taskLaunchMode.
  ///
  /// In en, this message translates to:
  /// **'Launch mode'**
  String get taskLaunchMode;

  /// No description provided for @taskLaunchAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get taskLaunchAuto;

  /// No description provided for @taskLaunchManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get taskLaunchManual;

  /// No description provided for @taskAgentProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get taskAgentProvider;

  /// No description provided for @taskAgentModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get taskAgentModel;

  /// No description provided for @taskAgentConfirmations.
  ///
  /// In en, this message translates to:
  /// **'Confirmations'**
  String get taskAgentConfirmations;

  /// No description provided for @taskAgentToolAutoMode.
  ///
  /// In en, this message translates to:
  /// **'Tool auto mode'**
  String get taskAgentToolAutoMode;

  /// No description provided for @taskAgentTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get taskAgentTools;

  /// No description provided for @taskAgentToolsLoading.
  ///
  /// In en, this message translates to:
  /// **'Tool list is loading'**
  String get taskAgentToolsLoading;

  /// No description provided for @taskAgentToolsNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale tools are not loaded'**
  String get taskAgentToolsNotLoaded;

  /// No description provided for @taskCodeWhaleUnavailable.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale is unavailable'**
  String get taskCodeWhaleUnavailable;

  /// No description provided for @taskAgentToolsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load agent tools: {error}'**
  String taskAgentToolsLoadFailed(Object error);

  /// No description provided for @taskAgentWorkspacesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load workspaces: {error}'**
  String taskAgentWorkspacesLoadFailed(Object error);

  /// No description provided for @taskContinueWork.
  ///
  /// In en, this message translates to:
  /// **'Continue work'**
  String get taskContinueWork;

  /// No description provided for @taskSaveTaskFirst.
  ///
  /// In en, this message translates to:
  /// **'Save the task first'**
  String get taskSaveTaskFirst;

  /// No description provided for @taskSaveTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a task title'**
  String get taskSaveTitleRequired;

  /// No description provided for @taskSaveGroupNotInProject.
  ///
  /// In en, this message translates to:
  /// **'Selected group is not in the project.'**
  String get taskSaveGroupNotInProject;

  /// No description provided for @taskSaveGroupCreateNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No permission to create a task in this group.'**
  String get taskSaveGroupCreateNoAccess;

  /// No description provided for @taskSaveAssigneesOutsideGroup.
  ///
  /// In en, this message translates to:
  /// **'Assignees must belong to the selected group.'**
  String get taskSaveAssigneesOutsideGroup;

  /// No description provided for @taskSaveInvalidStatus.
  ///
  /// In en, this message translates to:
  /// **'Invalid task status.'**
  String get taskSaveInvalidStatus;

  /// No description provided for @taskSaveInvalidPriority.
  ///
  /// In en, this message translates to:
  /// **'Invalid task priority.'**
  String get taskSaveInvalidPriority;

  /// No description provided for @taskSaveInvalidReminders.
  ///
  /// In en, this message translates to:
  /// **'Invalid reminder intervals.'**
  String get taskSaveInvalidReminders;

  /// No description provided for @taskSaveGenericFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not save task.'**
  String get taskSaveGenericFailure;

  /// No description provided for @taskAgentContinueNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No permission to continue agent'**
  String get taskAgentContinueNoAccess;

  /// No description provided for @taskAgentContinuesFreshCard.
  ///
  /// In en, this message translates to:
  /// **'Agent continues with the fresh task card'**
  String get taskAgentContinuesFreshCard;

  /// No description provided for @taskAgentContinueFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not continue agent: {error}'**
  String taskAgentContinueFailed(Object error);

  /// No description provided for @taskActivityAgentSessionRequested.
  ///
  /// In en, this message translates to:
  /// **'requested a new agent chat'**
  String get taskActivityAgentSessionRequested;

  /// No description provided for @taskActivityAgentSessionStartFailed.
  ///
  /// In en, this message translates to:
  /// **'could not start agent chat'**
  String get taskActivityAgentSessionStartFailed;

  /// No description provided for @taskActivityAgentSessionResumed.
  ///
  /// In en, this message translates to:
  /// **'continued agent chat'**
  String get taskActivityAgentSessionResumed;

  /// No description provided for @taskActivityAgentSessionResumeFailed.
  ///
  /// In en, this message translates to:
  /// **'could not continue agent chat'**
  String get taskActivityAgentSessionResumeFailed;

  /// No description provided for @taskActivityAgentSessionError.
  ///
  /// In en, this message translates to:
  /// **'received an agent chat error'**
  String get taskActivityAgentSessionError;

  /// No description provided for @taskActivityAgentSessionLinked.
  ///
  /// In en, this message translates to:
  /// **'linked agent chat'**
  String get taskActivityAgentSessionLinked;

  /// No description provided for @taskActivityAgentExistingSessionLinked.
  ///
  /// In en, this message translates to:
  /// **'linked existing agent chat'**
  String get taskActivityAgentExistingSessionLinked;

  /// No description provided for @taskActivityAgentAutoMovedToStatus.
  ///
  /// In en, this message translates to:
  /// **'automatically moved card to {status}'**
  String taskActivityAgentAutoMovedToStatus(Object status);

  /// No description provided for @taskActivityAgentQueueWaitingReview.
  ///
  /// In en, this message translates to:
  /// **'waiting for card review'**
  String get taskActivityAgentQueueWaitingReview;

  /// No description provided for @taskActivityAgentQueueCompleted.
  ///
  /// In en, this message translates to:
  /// **'completed agent queue'**
  String get taskActivityAgentQueueCompleted;

  /// No description provided for @taskActivityAgentQueueNeedsMoreWork.
  ///
  /// In en, this message translates to:
  /// **'waiting for more changes'**
  String get taskActivityAgentQueueNeedsMoreWork;

  /// No description provided for @taskActivityAgentStatusChanged.
  ///
  /// In en, this message translates to:
  /// **'moved card to {status}'**
  String taskActivityAgentStatusChanged(Object status);

  /// No description provided for @taskActivityAgentCardUpdated.
  ///
  /// In en, this message translates to:
  /// **'updated task card'**
  String get taskActivityAgentCardUpdated;

  /// No description provided for @taskAgentPlanTitle.
  ///
  /// In en, this message translates to:
  /// **'Agent plan'**
  String get taskAgentPlanTitle;

  /// No description provided for @taskAgentQueueStepFailed.
  ///
  /// In en, this message translates to:
  /// **'One of the agent steps did not complete: {status}'**
  String taskAgentQueueStepFailed(Object status);

  /// No description provided for @taskAgentQueueTaskCardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'family-task-card is unavailable. Agent queue stopped.'**
  String get taskAgentQueueTaskCardUnavailable;

  /// No description provided for @taskAgentSkills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get taskAgentSkills;

  /// No description provided for @taskAgentCommands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get taskAgentCommands;

  /// No description provided for @taskAgentAvailableCount.
  ///
  /// In en, this message translates to:
  /// **'Available: {count}'**
  String taskAgentAvailableCount(int count);

  /// No description provided for @taskAgentQueue.
  ///
  /// In en, this message translates to:
  /// **'Execution queue'**
  String get taskAgentQueue;

  /// No description provided for @taskAgentQueueHint.
  ///
  /// In en, this message translates to:
  /// **'Select tools; the work step will run last'**
  String get taskAgentQueueHint;

  /// No description provided for @taskMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get taskMoveUp;

  /// No description provided for @taskMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Down'**
  String get taskMoveDown;

  /// No description provided for @taskWorkStep.
  ///
  /// In en, this message translates to:
  /// **'Task work'**
  String get taskWorkStep;

  /// No description provided for @taskWorkStepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Checklists, comments, and task files are required'**
  String get taskWorkStepSubtitle;

  /// No description provided for @taskTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get taskTitle;

  /// No description provided for @taskDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get taskDetails;

  /// No description provided for @chatTaskDraft.
  ///
  /// In en, this message translates to:
  /// **'Task draft'**
  String get chatTaskDraft;

  /// No description provided for @taskSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get taskSummary;

  /// No description provided for @taskComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get taskComments;

  /// No description provided for @taskCommentComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Comment or caption'**
  String get taskCommentComposerHint;

  /// No description provided for @taskCommentActions.
  ///
  /// In en, this message translates to:
  /// **'Comment actions'**
  String get taskCommentActions;

  /// No description provided for @taskReplyToComment.
  ///
  /// In en, this message translates to:
  /// **'Reply to comment'**
  String get taskReplyToComment;

  /// No description provided for @taskEditingComment.
  ///
  /// In en, this message translates to:
  /// **'Editing comment'**
  String get taskEditingComment;

  /// No description provided for @taskCommentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Comment deleted'**
  String get taskCommentDeleted;

  /// No description provided for @taskCommentFallback.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get taskCommentFallback;

  /// No description provided for @taskActivityCommentEdited.
  ///
  /// In en, this message translates to:
  /// **'edited a comment'**
  String get taskActivityCommentEdited;

  /// No description provided for @taskActivityCommentAdded.
  ///
  /// In en, this message translates to:
  /// **'added a comment'**
  String get taskActivityCommentAdded;

  /// No description provided for @taskActivityCommentAddedWithAttachment.
  ///
  /// In en, this message translates to:
  /// **'added a comment with an attachment'**
  String get taskActivityCommentAddedWithAttachment;

  /// No description provided for @taskActivityCommentReplied.
  ///
  /// In en, this message translates to:
  /// **'replied to a comment'**
  String get taskActivityCommentReplied;

  /// No description provided for @taskActivityCommentDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted a comment'**
  String get taskActivityCommentDeleted;

  /// No description provided for @taskActivityChecklistAdded.
  ///
  /// In en, this message translates to:
  /// **'created checklist "{title}"'**
  String taskActivityChecklistAdded(Object title);

  /// No description provided for @taskActivityChecklistItemAdded.
  ///
  /// In en, this message translates to:
  /// **'added item "{item}"'**
  String taskActivityChecklistItemAdded(Object item);

  /// No description provided for @taskActivityChecklistItemDone.
  ///
  /// In en, this message translates to:
  /// **'completed checklist item'**
  String get taskActivityChecklistItemDone;

  /// No description provided for @taskActivityChecklistItemReopened.
  ///
  /// In en, this message translates to:
  /// **'reopened checklist item'**
  String get taskActivityChecklistItemReopened;

  /// No description provided for @taskActivityChecklistRenamed.
  ///
  /// In en, this message translates to:
  /// **'renamed checklist to "{title}"'**
  String taskActivityChecklistRenamed(Object title);

  /// No description provided for @taskActivityChecklistDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted checklist "{title}"'**
  String taskActivityChecklistDeleted(Object title);

  /// No description provided for @taskActivityChecklistItemRenamed.
  ///
  /// In en, this message translates to:
  /// **'edited checklist item'**
  String get taskActivityChecklistItemRenamed;

  /// No description provided for @taskActivityChecklistItemDeleted.
  ///
  /// In en, this message translates to:
  /// **'deleted checklist item'**
  String get taskActivityChecklistItemDeleted;

  /// No description provided for @taskCancelCommentAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get taskCancelCommentAction;

  /// No description provided for @taskDeleteCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete comment?'**
  String get taskDeleteCommentTitle;

  /// No description provided for @taskDeleteCommentMessage.
  ///
  /// In en, this message translates to:
  /// **'The comment will be removed from the task card.'**
  String get taskDeleteCommentMessage;

  /// No description provided for @taskOpenPhotoAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open photo'**
  String get taskOpenPhotoAttachment;

  /// No description provided for @taskOpenFileAttachment.
  ///
  /// In en, this message translates to:
  /// **'Open file'**
  String get taskOpenFileAttachment;

  /// No description provided for @taskRemoveAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get taskRemoveAttachment;

  /// No description provided for @taskPhotoCaptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo caption'**
  String get taskPhotoCaptionTitle;

  /// No description provided for @taskFileCaptionTitle.
  ///
  /// In en, this message translates to:
  /// **'File caption'**
  String get taskFileCaptionTitle;

  /// No description provided for @taskAttachmentCaptionHint.
  ///
  /// In en, this message translates to:
  /// **'Add caption (optional)'**
  String get taskAttachmentCaptionHint;

  /// No description provided for @taskSkipAttachmentCaption.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get taskSkipAttachmentCaption;

  /// No description provided for @taskAttachmentUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload attachment: {error}'**
  String taskAttachmentUploadFailed(Object error);

  /// No description provided for @taskAttachmentEmptyOrCorrupt.
  ///
  /// In en, this message translates to:
  /// **'The file is empty or corrupted.'**
  String get taskAttachmentEmptyOrCorrupt;

  /// No description provided for @taskAttachmentUploadMissingUrl.
  ///
  /// In en, this message translates to:
  /// **'The server did not return a file URL.'**
  String get taskAttachmentUploadMissingUrl;

  /// No description provided for @taskFileReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get taskFileReadFailed;

  /// No description provided for @taskFileOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open file'**
  String get taskFileOpenFailed;

  /// No description provided for @taskNoComments.
  ///
  /// In en, this message translates to:
  /// **'No comments'**
  String get taskNoComments;

  /// No description provided for @checklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get checklist;

  /// No description provided for @taskChecklists.
  ///
  /// In en, this message translates to:
  /// **'Checklists'**
  String get taskChecklists;

  /// No description provided for @taskNewChecklist.
  ///
  /// In en, this message translates to:
  /// **'New checklist'**
  String get taskNewChecklist;

  /// No description provided for @taskAddChecklist.
  ///
  /// In en, this message translates to:
  /// **'Add checklist'**
  String get taskAddChecklist;

  /// No description provided for @taskNoChecklists.
  ///
  /// In en, this message translates to:
  /// **'No checklists'**
  String get taskNoChecklists;

  /// No description provided for @taskEditChecklist.
  ///
  /// In en, this message translates to:
  /// **'Edit checklist'**
  String get taskEditChecklist;

  /// No description provided for @taskChecklistName.
  ///
  /// In en, this message translates to:
  /// **'Checklist name'**
  String get taskChecklistName;

  /// No description provided for @taskDeleteChecklist.
  ///
  /// In en, this message translates to:
  /// **'Delete checklist'**
  String get taskDeleteChecklist;

  /// No description provided for @taskDeleteChecklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete checklist?'**
  String get taskDeleteChecklistTitle;

  /// No description provided for @taskDeleteChecklistMessage.
  ///
  /// In en, this message translates to:
  /// **'The checklist and its items will be removed from the task.'**
  String get taskDeleteChecklistMessage;

  /// No description provided for @taskEditChecklistItem.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get taskEditChecklistItem;

  /// No description provided for @taskChecklistItemText.
  ///
  /// In en, this message translates to:
  /// **'Item text'**
  String get taskChecklistItemText;

  /// No description provided for @taskDeleteChecklistItem.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get taskDeleteChecklistItem;

  /// No description provided for @taskDeleteChecklistItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete item?'**
  String get taskDeleteChecklistItemTitle;

  /// No description provided for @taskDeleteChecklistItemMessage.
  ///
  /// In en, this message translates to:
  /// **'The item will be removed from the checklist.'**
  String get taskDeleteChecklistItemMessage;

  /// No description provided for @taskChecklistItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get taskChecklistItem;

  /// No description provided for @taskAddChecklistItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get taskAddChecklistItem;

  /// No description provided for @taskActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get taskActivity;

  /// No description provided for @taskActivityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get taskActivityEmpty;

  /// No description provided for @actionItems.
  ///
  /// In en, this message translates to:
  /// **'Action items'**
  String get actionItems;

  /// No description provided for @decisions.
  ///
  /// In en, this message translates to:
  /// **'Decisions'**
  String get decisions;

  /// No description provided for @blockers.
  ///
  /// In en, this message translates to:
  /// **'Blockers'**
  String get blockers;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// No description provided for @createTask.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get createTask;

  /// No description provided for @taskFromChat.
  ///
  /// In en, this message translates to:
  /// **'Task from chat'**
  String get taskFromChat;

  /// No description provided for @taskProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get taskProject;

  /// No description provided for @taskGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get taskGroup;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDate;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @taskStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get taskStatus;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @workflowTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get workflowTodo;

  /// No description provided for @workflowInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workflowInProgress;

  /// No description provided for @workflowInReview.
  ///
  /// In en, this message translates to:
  /// **'In review'**
  String get workflowInReview;

  /// No description provided for @workflowDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get workflowDone;

  /// No description provided for @workflowArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get workflowArchive;

  /// No description provided for @reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminder;

  /// No description provided for @taskReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get taskReminders;

  /// No description provided for @taskReminderBefore24Hours.
  ///
  /// In en, this message translates to:
  /// **'24 hours before'**
  String get taskReminderBefore24Hours;

  /// No description provided for @taskReminderBefore12Hours.
  ///
  /// In en, this message translates to:
  /// **'12 hours before'**
  String get taskReminderBefore12Hours;

  /// No description provided for @taskReminderBefore3Hours.
  ///
  /// In en, this message translates to:
  /// **'3 hours before'**
  String get taskReminderBefore3Hours;

  /// No description provided for @taskReminderBefore2Hours.
  ///
  /// In en, this message translates to:
  /// **'2 hours before'**
  String get taskReminderBefore2Hours;

  /// No description provided for @taskReminderBefore1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour before'**
  String get taskReminderBefore1Hour;

  /// No description provided for @taskReminderBefore30Minutes.
  ///
  /// In en, this message translates to:
  /// **'30 minutes before'**
  String get taskReminderBefore30Minutes;

  /// No description provided for @taskReminderBefore15Minutes.
  ///
  /// In en, this message translates to:
  /// **'15 minutes before'**
  String get taskReminderBefore15Minutes;

  /// No description provided for @taskReminderBefore5Minutes.
  ///
  /// In en, this message translates to:
  /// **'5 minutes before'**
  String get taskReminderBefore5Minutes;

  /// No description provided for @participants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// No description provided for @taskAssignees.
  ///
  /// In en, this message translates to:
  /// **'Assignees'**
  String get taskAssignees;

  /// No description provided for @taskDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration estimate (min)'**
  String get taskDuration;

  /// No description provided for @selectProject.
  ///
  /// In en, this message translates to:
  /// **'Select project'**
  String get selectProject;

  /// No description provided for @selectGroup.
  ///
  /// In en, this message translates to:
  /// **'Select group'**
  String get selectGroup;

  /// No description provided for @projectHasNoGroups.
  ///
  /// In en, this message translates to:
  /// **'This project has no groups.'**
  String get projectHasNoGroups;

  /// No description provided for @selectProjectGroup.
  ///
  /// In en, this message translates to:
  /// **'Select a project group.'**
  String get selectProjectGroup;

  /// No description provided for @groupMembersMissing.
  ///
  /// In en, this message translates to:
  /// **'No group members were found in contacts.'**
  String get groupMembersMissing;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @editProject.
  ///
  /// In en, this message translates to:
  /// **'Edit project'**
  String get editProject;

  /// No description provided for @projectNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameLabel;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @projectNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter project name'**
  String get projectNameRequired;

  /// No description provided for @projectSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String projectSaveFailed(Object error);

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @editGroup.
  ///
  /// In en, this message translates to:
  /// **'Edit group'**
  String get editGroup;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameLabel;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @refreshContacts.
  ///
  /// In en, this message translates to:
  /// **'Refresh contacts'**
  String get refreshContacts;

  /// No description provided for @noContacts.
  ///
  /// In en, this message translates to:
  /// **'No contacts. Add contacts in Messenger.'**
  String get noContacts;

  /// No description provided for @noRegisteredPhoneContacts.
  ///
  /// In en, this message translates to:
  /// **'No registered phone contacts'**
  String get noRegisteredPhoneContacts;

  /// No description provided for @addToFamily.
  ///
  /// In en, this message translates to:
  /// **'Add to family'**
  String get addToFamily;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter group name'**
  String get groupNameRequired;

  /// No description provided for @groupMemberRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one participant'**
  String get groupMemberRequired;

  /// No description provided for @groupSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String groupSaveFailed(Object error);

  /// No description provided for @projectsSection.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get projectsSection;

  /// No description provided for @createProjectAction.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProjectAction;

  /// No description provided for @createGroupAction.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroupAction;

  /// No description provided for @projectChats.
  ///
  /// In en, this message translates to:
  /// **'Project chats'**
  String get projectChats;

  /// No description provided for @regularGroups.
  ///
  /// In en, this message translates to:
  /// **'Regular groups'**
  String get regularGroups;

  /// No description provided for @chatParticipantsCount.
  ///
  /// In en, this message translates to:
  /// **'Participants: {count}'**
  String chatParticipantsCount(int count);

  /// No description provided for @noProjectsYetAction.
  ///
  /// In en, this message translates to:
  /// **'No projects yet. Press + to create one.'**
  String get noProjectsYetAction;

  /// No description provided for @noGroupsYetAction.
  ///
  /// In en, this message translates to:
  /// **'No groups yet. Press + to create one.'**
  String get noGroupsYetAction;

  /// No description provided for @projectControlCreateProjectHint.
  ///
  /// In en, this message translates to:
  /// **'Create a project to connect chat and agent.'**
  String get projectControlCreateProjectHint;

  /// No description provided for @projectControlChatsNotLinked.
  ///
  /// In en, this message translates to:
  /// **'No linked chats'**
  String get projectControlChatsNotLinked;

  /// No description provided for @projectControlChatsCount.
  ///
  /// In en, this message translates to:
  /// **'Chats: {count}'**
  String projectControlChatsCount(int count);

  /// No description provided for @projectControlWorkspaceNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Workspace not selected'**
  String get projectControlWorkspaceNotSelected;

  /// No description provided for @projectControlWorkspaceChip.
  ///
  /// In en, this message translates to:
  /// **'Workspace: {label}'**
  String projectControlWorkspaceChip(Object label);

  /// No description provided for @projectControlWorkspaceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Workspace: {label} (no access)'**
  String projectControlWorkspaceUnavailable(Object label);

  /// No description provided for @projectControlNoAgentAccess.
  ///
  /// In en, this message translates to:
  /// **'No agent access'**
  String get projectControlNoAgentAccess;

  /// No description provided for @projectControlWorkspaceLoading.
  ///
  /// In en, this message translates to:
  /// **'Workspace is loading'**
  String get projectControlWorkspaceLoading;

  /// No description provided for @projectControlAgentAvailable.
  ///
  /// In en, this message translates to:
  /// **'Agent available'**
  String get projectControlAgentAvailable;

  /// No description provided for @projectControlLinkedChats.
  ///
  /// In en, this message translates to:
  /// **'Linked chats'**
  String get projectControlLinkedChats;

  /// No description provided for @projectControlAssignGroupForChat.
  ///
  /// In en, this message translates to:
  /// **'Assign a group to the project to create a project chat.'**
  String get projectControlAssignGroupForChat;

  /// No description provided for @projectControlCreateChat.
  ///
  /// In en, this message translates to:
  /// **'Create project chat'**
  String get projectControlCreateChat;

  /// No description provided for @projectControlRefreshChat.
  ///
  /// In en, this message translates to:
  /// **'Refresh project chat'**
  String get projectControlRefreshChat;

  /// No description provided for @projectControlAnalyzeChat.
  ///
  /// In en, this message translates to:
  /// **'Chat analysis'**
  String get projectControlAnalyzeChat;

  /// No description provided for @projectControlDraftTask.
  ///
  /// In en, this message translates to:
  /// **'Task draft'**
  String get projectControlDraftTask;

  /// No description provided for @projectControlStartAgent.
  ///
  /// In en, this message translates to:
  /// **'Start agent'**
  String get projectControlStartAgent;

  /// No description provided for @projectAgentMenu.
  ///
  /// In en, this message translates to:
  /// **'Project agent'**
  String get projectAgentMenu;

  /// No description provided for @projectControlProjectStatus.
  ///
  /// In en, this message translates to:
  /// **'Project status'**
  String get projectControlProjectStatus;

  /// No description provided for @homeProjectDescriptionMissing.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get homeProjectDescriptionMissing;

  /// No description provided for @homeProjectParticipants.
  ///
  /// In en, this message translates to:
  /// **'Participants: {members}'**
  String homeProjectParticipants(Object members);

  /// No description provided for @homeProjectWorkspaceNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Workspace is not selected'**
  String get homeProjectWorkspaceNotSelected;

  /// No description provided for @homeProjectWorkspaceHint.
  ///
  /// In en, this message translates to:
  /// **'Select workspace in Project Control Center'**
  String get homeProjectWorkspaceHint;

  /// No description provided for @homeProjectAgentAvailableByButton.
  ///
  /// In en, this message translates to:
  /// **'Agent is available from the button'**
  String get homeProjectAgentAvailableByButton;

  /// No description provided for @homeProjectAgentNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No access to AI agent'**
  String get homeProjectAgentNoAccess;

  /// No description provided for @homeProjectActiveAgentSession.
  ///
  /// In en, this message translates to:
  /// **'Active agent session'**
  String get homeProjectActiveAgentSession;

  /// No description provided for @workspaceBridgeNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Workspace list has not loaded yet.'**
  String get workspaceBridgeNotLoaded;

  /// No description provided for @workspaceBridgeEmpty.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale returned no workspaces.'**
  String get workspaceBridgeEmpty;

  /// No description provided for @workspaceBridgeLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded workspaces: {count}'**
  String workspaceBridgeLoaded(int count);

  /// No description provided for @primaryWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Primary workspace'**
  String get primaryWorkspace;

  /// No description provided for @refreshWorkspaceList.
  ///
  /// In en, this message translates to:
  /// **'Refresh workspaces'**
  String get refreshWorkspaceList;

  /// No description provided for @workspaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, id, or path'**
  String get workspaceSearchHint;

  /// No description provided for @workspaceFoundSummary.
  ///
  /// In en, this message translates to:
  /// **'Found: {found} of {total}. Source: {source}'**
  String workspaceFoundSummary(int found, int total, Object source);

  /// No description provided for @workspaceSourceBackendAccess.
  ///
  /// In en, this message translates to:
  /// **'backend access'**
  String get workspaceSourceBackendAccess;

  /// No description provided for @workspaceSourceCodeWhale.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale'**
  String get workspaceSourceCodeWhale;

  /// No description provided for @clearWorkspaceBinding.
  ///
  /// In en, this message translates to:
  /// **'Clear binding'**
  String get clearWorkspaceBinding;

  /// No description provided for @projectAgentDisabledAfterClearing.
  ///
  /// In en, this message translates to:
  /// **'The project agent will be disabled.'**
  String get projectAgentDisabledAfterClearing;

  /// No description provided for @noWorkspacesFound.
  ///
  /// In en, this message translates to:
  /// **'No workspaces found.'**
  String get noWorkspacesFound;

  /// No description provided for @projectWorkspaceCleared.
  ///
  /// In en, this message translates to:
  /// **'Project workspace cleared.'**
  String get projectWorkspaceCleared;

  /// No description provided for @projectWorkspaceSaved.
  ///
  /// In en, this message translates to:
  /// **'Project workspace saved.'**
  String get projectWorkspaceSaved;

  /// No description provided for @projectWorkspaceSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save project workspace.'**
  String get projectWorkspaceSaveFailed;

  /// No description provided for @projectChatReady.
  ///
  /// In en, this message translates to:
  /// **'Project chat \"{title}\" is ready.'**
  String projectChatReady(Object title);

  /// No description provided for @projectChatCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create project chat: {error}'**
  String projectChatCreateFailed(Object error);

  /// No description provided for @openProjectChatHint.
  ///
  /// In en, this message translates to:
  /// **'Open the project chat.'**
  String get openProjectChatHint;

  /// No description provided for @selectWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Select workspace'**
  String get selectWorkspace;

  /// No description provided for @changeWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Change workspace'**
  String get changeWorkspace;

  /// No description provided for @workspaceNotSelectedSentence.
  ///
  /// In en, this message translates to:
  /// **'Workspace not selected.'**
  String get workspaceNotSelectedSentence;

  /// No description provided for @workspaceSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {label}.'**
  String workspaceSelected(Object label);

  /// No description provided for @workspaceControlAvailable.
  ///
  /// In en, this message translates to:
  /// **'{selectedText} Available: {count}.'**
  String workspaceControlAvailable(Object selectedText, int count);

  /// No description provided for @noAvailableWorkspacesToSelect.
  ///
  /// In en, this message translates to:
  /// **'No available workspaces to select.'**
  String get noAvailableWorkspacesToSelect;

  /// No description provided for @workspaceSettingLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading workspace setting...'**
  String get workspaceSettingLoading;

  /// No description provided for @refreshWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Refresh workspaces'**
  String get refreshWorkspaces;

  /// No description provided for @selectAction.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectAction;

  /// No description provided for @projectGroupsSummary.
  ///
  /// In en, this message translates to:
  /// **'Groups: {groups}'**
  String projectGroupsSummary(Object groups);

  /// No description provided for @groupParticipantsSummary.
  ///
  /// In en, this message translates to:
  /// **'Participants: {participants}'**
  String groupParticipantsSummary(Object participants);

  /// No description provided for @deleteProjectTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get deleteProjectTitle;

  /// No description provided for @deleteProjectMessage.
  ///
  /// In en, this message translates to:
  /// **'The project and group links will be deleted.'**
  String get deleteProjectMessage;

  /// No description provided for @deleteGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete group?'**
  String get deleteGroupTitle;

  /// No description provided for @deleteGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'The group will be removed from all projects.'**
  String get deleteGroupMessage;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get connecting;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get reconnecting;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get disconnected;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectionError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @saveName.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get saveName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @phoneNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumberLabel;

  /// No description provided for @initialProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with phone number'**
  String get initialProfileTitle;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @administration.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get administration;

  /// No description provided for @profileAdminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Users, projects, workspaces, and agent roles'**
  String get profileAdminSubtitle;

  /// No description provided for @adminNoAccess.
  ///
  /// In en, this message translates to:
  /// **'No administration access'**
  String get adminNoAccess;

  /// No description provided for @adminBridgeNotConnected.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale workspaces are not connected'**
  String get adminBridgeNotConnected;

  /// No description provided for @adminCodeWhaleDisabled.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale disabled'**
  String get adminCodeWhaleDisabled;

  /// No description provided for @adminNewAccess.
  ///
  /// In en, this message translates to:
  /// **'New access'**
  String get adminNewAccess;

  /// No description provided for @adminContactFromContacts.
  ///
  /// In en, this message translates to:
  /// **'Contact from contacts'**
  String get adminContactFromContacts;

  /// No description provided for @adminContactsNotFound.
  ///
  /// In en, this message translates to:
  /// **'No contacts found'**
  String get adminContactsNotFound;

  /// No description provided for @adminWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get adminWorkspace;

  /// No description provided for @adminRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminRole;

  /// No description provided for @adminGrantAccess.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get adminGrantAccess;

  /// No description provided for @adminGrantedAccess.
  ///
  /// In en, this message translates to:
  /// **'Granted access'**
  String get adminGrantedAccess;

  /// No description provided for @adminNoActiveAccess.
  ///
  /// In en, this message translates to:
  /// **'No active access yet'**
  String get adminNoActiveAccess;

  /// No description provided for @adminRevokeAccess.
  ///
  /// In en, this message translates to:
  /// **'Revoke access'**
  String get adminRevokeAccess;

  /// No description provided for @adminAgentRoles.
  ///
  /// In en, this message translates to:
  /// **'Agent roles'**
  String get adminAgentRoles;

  /// No description provided for @adminUsersCount.
  ///
  /// In en, this message translates to:
  /// **'Users: {count}'**
  String adminUsersCount(int count);

  /// No description provided for @adminWorkspacesCount.
  ///
  /// In en, this message translates to:
  /// **'Workspaces: {count}'**
  String adminWorkspacesCount(int count);

  /// No description provided for @adminProjectsCount.
  ///
  /// In en, this message translates to:
  /// **'Projects: {count}'**
  String adminProjectsCount(int count);

  /// No description provided for @adminRoleWorkspaceUser.
  ///
  /// In en, this message translates to:
  /// **'Workspace member'**
  String get adminRoleWorkspaceUser;

  /// No description provided for @adminRoleWorkspaceUserDescription.
  ///
  /// In en, this message translates to:
  /// **'Can view the workspace and use AI.'**
  String get adminRoleWorkspaceUserDescription;

  /// No description provided for @adminRoleAgentOperator.
  ///
  /// In en, this message translates to:
  /// **'Agent operator'**
  String get adminRoleAgentOperator;

  /// No description provided for @adminRoleAgentOperatorDescription.
  ///
  /// In en, this message translates to:
  /// **'Can launch agent chats from tasks and run work in them.'**
  String get adminRoleAgentOperatorDescription;

  /// No description provided for @adminRoleWorkspaceAdmin.
  ///
  /// In en, this message translates to:
  /// **'Workspace administrator'**
  String get adminRoleWorkspaceAdmin;

  /// No description provided for @adminRoleWorkspaceAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Can manage access and advanced agent actions.'**
  String get adminRoleWorkspaceAdminDescription;

  /// No description provided for @avatarUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload avatar: {error}'**
  String avatarUploadFailed(Object error);

  /// No description provided for @nameSaved.
  ///
  /// In en, this message translates to:
  /// **'Name saved'**
  String get nameSaved;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @sticker.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get sticker;

  /// No description provided for @stickers.
  ///
  /// In en, this message translates to:
  /// **'Stickers'**
  String get stickers;

  /// No description provided for @noStickersLoaded.
  ///
  /// In en, this message translates to:
  /// **'No stickers loaded yet'**
  String get noStickersLoaded;

  /// No description provided for @stickerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Sticker unavailable'**
  String get stickerUnavailable;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noSearchResults;

  /// No description provided for @allStyles.
  ///
  /// In en, this message translates to:
  /// **'All styles'**
  String get allStyles;

  /// No description provided for @allTopics.
  ///
  /// In en, this message translates to:
  /// **'All topics'**
  String get allTopics;

  /// No description provided for @voiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get voiceMessage;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'typing...'**
  String get typing;

  /// No description provided for @profileTyping.
  ///
  /// In en, this message translates to:
  /// **'{profile} is typing...'**
  String profileTyping(String profile);

  /// No description provided for @peopleTyping.
  ///
  /// In en, this message translates to:
  /// **'{count} people are typing...'**
  String peopleTyping(int count);

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get offline;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get markRead;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// No description provided for @workspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspaces;

  /// No description provided for @attachFolder.
  ///
  /// In en, this message translates to:
  /// **'Attach folder'**
  String get attachFolder;

  /// No description provided for @createWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Create workspace'**
  String get createWorkspace;

  /// No description provided for @codeWhaleConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to CodeWhale...'**
  String get codeWhaleConnecting;

  /// No description provided for @codeWhaleErrorFallback.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale error'**
  String get codeWhaleErrorFallback;

  /// No description provided for @codeWhaleThinking.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale is thinking...'**
  String get codeWhaleThinking;

  /// No description provided for @codeWhaleStartingEvent.
  ///
  /// In en, this message translates to:
  /// **'Starting CodeWhale'**
  String get codeWhaleStartingEvent;

  /// No description provided for @codeWhaleFileAttachedEvent.
  ///
  /// In en, this message translates to:
  /// **'File attached: {path}'**
  String codeWhaleFileAttachedEvent(Object path);

  /// No description provided for @codeWhaleFileAttachedStatus.
  ///
  /// In en, this message translates to:
  /// **'File attached'**
  String get codeWhaleFileAttachedStatus;

  /// No description provided for @codeWhaleReadyStatus.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale ready'**
  String get codeWhaleReadyStatus;

  /// No description provided for @codeWhaleNewWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get codeWhaleNewWorkspaceTitle;

  /// No description provided for @workspaceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workspaceNameLabel;

  /// No description provided for @codeWhalePhotoCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo comment'**
  String get codeWhalePhotoCommentTitle;

  /// No description provided for @codeWhaleDocumentCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'Document comment'**
  String get codeWhaleDocumentCommentTitle;

  /// No description provided for @codeWhaleUploadPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Empty = save only'**
  String get codeWhaleUploadPromptHint;

  /// No description provided for @noWorkspacesYet.
  ///
  /// In en, this message translates to:
  /// **'No workspaces yet'**
  String get noWorkspacesYet;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @createSession.
  ///
  /// In en, this message translates to:
  /// **'Create session'**
  String get createSession;

  /// No description provided for @manageSession.
  ///
  /// In en, this message translates to:
  /// **'Manage session'**
  String get manageSession;

  /// No description provided for @noSessionsYet.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get noSessionsYet;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get running;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'port'**
  String get port;

  /// No description provided for @waitingToStart.
  ///
  /// In en, this message translates to:
  /// **'Waiting to start'**
  String get waitingToStart;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @killed.
  ///
  /// In en, this message translates to:
  /// **'Killed'**
  String get killed;

  /// No description provided for @unknownStatus.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get unknownStatus;

  /// No description provided for @folderSelection.
  ///
  /// In en, this message translates to:
  /// **'Folder selection'**
  String get folderSelection;

  /// No description provided for @refreshFolders.
  ///
  /// In en, this message translates to:
  /// **'Refresh folders'**
  String get refreshFolders;

  /// No description provided for @currentFolder.
  ///
  /// In en, this message translates to:
  /// **'Current folder'**
  String get currentFolder;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get copyPath;

  /// No description provided for @parentFolder.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get parentFolder;

  /// No description provided for @noFoldersHere.
  ///
  /// In en, this message translates to:
  /// **'No folders here'**
  String get noFoldersHere;

  /// No description provided for @connectThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Connect this folder'**
  String get connectThisFolder;

  /// No description provided for @sessionHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Session history is empty'**
  String get sessionHistoryEmpty;

  /// No description provided for @attachPhoto.
  ///
  /// In en, this message translates to:
  /// **'Attach photo'**
  String get attachPhoto;

  /// No description provided for @attachDocument.
  ///
  /// In en, this message translates to:
  /// **'Attach document'**
  String get attachDocument;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @workProgress.
  ///
  /// In en, this message translates to:
  /// **'Work progress'**
  String get workProgress;

  /// No description provided for @stopGeneration.
  ///
  /// In en, this message translates to:
  /// **'Stop generation'**
  String get stopGeneration;

  /// No description provided for @sessionTab.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sessionTab;

  /// No description provided for @filesTab.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesTab;

  /// No description provided for @commandsTab.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get commandsTab;

  /// No description provided for @sessionStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get sessionStatusLabel;

  /// No description provided for @sessionPidLabel.
  ///
  /// In en, this message translates to:
  /// **'PID'**
  String get sessionPidLabel;

  /// No description provided for @sessionPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get sessionPortLabel;

  /// No description provided for @sessionEventsLabel.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get sessionEventsLabel;

  /// No description provided for @noValue.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get noValue;

  /// No description provided for @sessionIdleStatus.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get sessionIdleStatus;

  /// No description provided for @sessionUnknownStatus.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get sessionUnknownStatus;

  /// No description provided for @restartWorker.
  ///
  /// In en, this message translates to:
  /// **'Restart worker'**
  String get restartWorker;

  /// No description provided for @stopSession.
  ///
  /// In en, this message translates to:
  /// **'Stop session'**
  String get stopSession;

  /// No description provided for @killStuckSession.
  ///
  /// In en, this message translates to:
  /// **'Kill stuck session'**
  String get killStuckSession;

  /// No description provided for @restartAction.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restartAction;

  /// No description provided for @stopAction.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopAction;

  /// No description provided for @killAction.
  ///
  /// In en, this message translates to:
  /// **'Kill'**
  String get killAction;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @projectRoot.
  ///
  /// In en, this message translates to:
  /// **'Project root'**
  String get projectRoot;

  /// No description provided for @upOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get upOneLevel;

  /// No description provided for @refreshFiles.
  ///
  /// In en, this message translates to:
  /// **'Refresh files'**
  String get refreshFiles;

  /// No description provided for @copyFileText.
  ///
  /// In en, this message translates to:
  /// **'Copy file text'**
  String get copyFileText;

  /// No description provided for @noFiles.
  ///
  /// In en, this message translates to:
  /// **'No files'**
  String get noFiles;

  /// No description provided for @insertPathInChat.
  ///
  /// In en, this message translates to:
  /// **'Insert path in chat'**
  String get insertPathInChat;

  /// No description provided for @previewFile.
  ///
  /// In en, this message translates to:
  /// **'Preview file'**
  String get previewFile;

  /// No description provided for @projectFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Files - {projectName}'**
  String projectFilesTitle(Object projectName);

  /// No description provided for @loadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Loading files...'**
  String get loadingFiles;

  /// No description provided for @folderEmpty.
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get folderEmpty;

  /// No description provided for @previewAction.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewAction;

  /// No description provided for @linkToChat.
  ///
  /// In en, this message translates to:
  /// **'Link to chat'**
  String get linkToChat;

  /// No description provided for @sessionCodeWhaleModes.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale modes'**
  String get sessionCodeWhaleModes;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @approvalPolicy.
  ///
  /// In en, this message translates to:
  /// **'Approval policy'**
  String get approvalPolicy;

  /// No description provided for @sandbox.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get sandbox;

  /// No description provided for @defaultValue.
  ///
  /// In en, this message translates to:
  /// **'default'**
  String get defaultValue;

  /// No description provided for @autoModeTools.
  ///
  /// In en, this message translates to:
  /// **'Tool auto mode'**
  String get autoModeTools;

  /// No description provided for @autoModeToolsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Run tools automatically'**
  String get autoModeToolsTooltip;

  /// No description provided for @autoModeToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Passes --auto to CodeWhale exec'**
  String get autoModeToolsSubtitle;

  /// No description provided for @codeWhaleCommandsLoading.
  ///
  /// In en, this message translates to:
  /// **'CodeWhale commands are loading...'**
  String get codeWhaleCommandsLoading;

  /// No description provided for @skills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skills;

  /// No description provided for @runSelected.
  ///
  /// In en, this message translates to:
  /// **'Run selected'**
  String get runSelected;

  /// No description provided for @chooseSkills.
  ///
  /// In en, this message translates to:
  /// **'Choose one or more skills'**
  String get chooseSkills;

  /// No description provided for @selectedSkillsCount.
  ///
  /// In en, this message translates to:
  /// **'Selected: {count}'**
  String selectedSkillsCount(int count);

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnostics;

  /// No description provided for @resetToken.
  ///
  /// In en, this message translates to:
  /// **'Reset token'**
  String get resetToken;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @notificationChannelName.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationChannelName;

  /// No description provided for @notificationChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Push notifications for tasks and reminders'**
  String get notificationChannelDesc;

  /// No description provided for @notificationNewMessage.
  ///
  /// In en, this message translates to:
  /// **'New message'**
  String get notificationNewMessage;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'ru': return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
