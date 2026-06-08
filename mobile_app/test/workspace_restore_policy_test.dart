import 'package:family_todo_mobile/features/workspaces/workspace_restore_policy.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/models/workspace_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspace restore policy', () {
    const workspaceA = WorkspaceItem(
      id: 'workspace-a',
      name: 'Workspace A',
      path: r'C:\Projects\a',
      status: WorkspaceStatus.available,
    );
    const workspaceB = WorkspaceItem(
      id: 'workspace-b',
      name: 'Workspace B',
      path: r'C:\Projects\b',
      status: WorkspaceStatus.available,
    );

    test('does not auto-restore saved workspace when menu opens', () {
      final result = workspaceToRestore(
        workspaces: const [workspaceA, workspaceB],
        savedWorkspaceId: 'workspace-b',
        activeWorkspace: null,
      );

      expect(result, isNull);
    });

    test('does not override active workspace', () {
      final result = workspaceToRestore(
        workspaces: const [workspaceA, workspaceB],
        savedWorkspaceId: 'workspace-b',
        activeWorkspace: workspaceA,
      );

      expect(result, isNull);
    });

    test('does not auto-open saved session when menu opens', () {
      const sessionA = WorkspaceSession(
        id: 'session-a',
        workspaceId: 'workspace-a',
        title: 'Session A',
        status: WorkspaceSessionStatus.idle,
      );
      const sessionB = WorkspaceSession(
        id: 'session-b',
        workspaceId: 'workspace-a',
        title: 'Session B',
        status: WorkspaceSessionStatus.idle,
      );

      final result = workspaceSessionToRestore(
        sessions: const [sessionA, sessionB],
        savedSessionId: 'session-b',
        activeSession: null,
      );

      expect(result, isNull);
    });
  });
}
