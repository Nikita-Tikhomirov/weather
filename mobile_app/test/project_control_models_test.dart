import 'package:family_todo_mobile/models/project_control_models.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Project control models', () {
    test('parse project control snapshot', () {
      final snapshot = ProjectControlSnapshot.fromJson(const {
        'snapshot': {
          'project': {
            'id': 'project-1',
            'name': 'Weather',
            'owner_key': 'nik',
          },
          'chat_bindings': [
            {
              'project_id': 'project-1',
              'conversation_key': 'grp:family:group-1',
              'group_id': 'group-1',
              'source': 'family_group',
              'is_primary': true,
              'title': 'Команда',
              'members': ['nik', 'nastya'],
            },
          ],
          'automation': {
            'project_id': 'project-1',
            'primary_workspace_id': 'weather',
            'agent_enabled': true,
            'default_agent_mode': 'planner',
            'chat_analysis_message_limit': 25,
          },
          'primary_workspace': {'id': 'weather'},
          'permissions': {
            'can_manage_project': true,
            'can_use_agent': true,
            'can_use_workspace': true,
          },
        },
      });

      expect(snapshot.project.id, 'project-1');
      expect(snapshot.primaryWorkspaceId, 'weather');
      expect(snapshot.canUseAgent, isTrue);
      expect(snapshot.chatBindings.single.displayTitle, 'Команда');
      expect(
        snapshot.bindingForConversation('grp:family:group-1')?.groupId,
        'group-1',
      );
    });

    test('keeps workspace empty when backend did not configure it', () {
      final snapshot = ProjectControlSnapshot.fromJson(const {
        'snapshot': {
          'project': {
            'id': 'project-1',
            'name': 'Weather',
            'owner_key': 'nik',
          },
          'chat_bindings': [],
          'automation': {
            'project_id': 'project-1',
            'primary_workspace_id': '',
          },
          'primary_workspace': {'id': ''},
          'permissions': {
            'can_manage_project': true,
            'can_use_agent': false,
            'can_use_workspace': false,
          },
        },
      });

      expect(snapshot.primaryWorkspaceId, isEmpty);
      expect(snapshot.automation.primaryWorkspaceId, isEmpty);
      expect(snapshot.canUseAgent, isFalse);
    });

    test('parse chat task draft and convert to task draft', () {
      final draft = ChatTaskDraft.fromJson(const {
        'draft': {
          'title': 'Собрать экран связей проекта',
          'details': 'Нужен новый UX для чатов и workspace.',
          'decisions': ['Проект является центром управления'],
          'action_items': ['Показать project chip в чате'],
          'blockers': ['Нет primary workspace'],
          'checklist': ['Backend endpoint', 'Flutter UI'],
          'assignees': ['nik'],
          'source_message_ids': ['msg-1', 'msg-2'],
          'priority': 'high',
        },
      });
      final taskDraft = draft.toTaskDraft(
        projectId: 'project-1',
        groupId: 'group-1',
      );

      expect(draft.priority, Priority.high);
      expect(taskDraft.projectId, 'project-1');
      expect(taskDraft.groupId, 'group-1');
      expect(taskDraft.title, 'Собрать экран связей проекта');
      expect(taskDraft.details, contains('Проект является центром управления'));
      expect(taskDraft.details, contains('msg-1'));
    });
  });
}
