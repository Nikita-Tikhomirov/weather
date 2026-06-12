import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_project.dart';

class ProjectChatStatusSheet extends StatelessWidget {
  const ProjectChatStatusSheet({
    super.key,
    required this.project,
    required this.conversationTitle,
    required this.members,
    required this.workspaceId,
    required this.canUseAi,
    required this.agentSessionId,
  });

  final TaskProject project;
  final String conversationTitle;
  final List<String> members;
  final String workspaceId;
  final bool canUseAi;
  final String agentSessionId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectDescription = project.description.trim();
    final cleanWorkspaceId = workspaceId.trim();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n?.projectControlProjectStatus ?? 'Статус проекта',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(project.name),
            subtitle: Text(
              projectDescription.isEmpty
                  ? l10n?.homeProjectDescriptionMissing ?? 'Описание не задано'
                  : projectDescription,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.forum_outlined),
            title: Text(conversationTitle),
            subtitle: Text(
              l10n?.homeProjectParticipants(members.join(', ')) ??
                  'Участники: ${members.join(', ')}',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.workspaces_outline),
            title: Text(
              cleanWorkspaceId.isEmpty
                  ? l10n?.homeProjectWorkspaceNotSelected ??
                      'Workspace не выбран'
                  : cleanWorkspaceId,
            ),
            subtitle: Text(
              cleanWorkspaceId.isEmpty
                  ? l10n?.homeProjectWorkspaceHint ??
                      'Выберите workspace в Project Control Center'
                  : canUseAi
                      ? l10n?.homeProjectAgentAvailableByButton ??
                          'Агент доступен по кнопке'
                      : l10n?.homeProjectAgentNoAccess ??
                          'Нет прав на AI-агента',
            ),
          ),
          if (agentSessionId.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(
                l10n?.homeProjectActiveAgentSession ?? 'Активная сессия агента',
              ),
              subtitle: Text(agentSessionId),
            ),
        ],
      ),
    );
  }
}
