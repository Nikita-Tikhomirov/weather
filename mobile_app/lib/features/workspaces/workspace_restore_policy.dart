import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

WorkspaceItem? workspaceToRestore({
  required List<WorkspaceItem> workspaces,
  required String savedWorkspaceId,
  required WorkspaceItem? activeWorkspace,
  bool restoreEnabled = false,
}) {
  if (!restoreEnabled ||
      activeWorkspace != null ||
      savedWorkspaceId.trim().isEmpty) {
    return null;
  }
  return workspaces.cast<WorkspaceItem?>().firstWhere(
        (workspace) => workspace?.id == savedWorkspaceId,
        orElse: () => null,
      );
}

WorkspaceSession? workspaceSessionToRestore({
  required List<WorkspaceSession> sessions,
  required String savedSessionId,
  required WorkspaceSession? activeSession,
  bool restoreEnabled = false,
}) {
  if (!restoreEnabled ||
      activeSession != null ||
      savedSessionId.trim().isEmpty) {
    return null;
  }
  return sessions.cast<WorkspaceSession?>().firstWhere(
        (session) => session?.id == savedSessionId,
        orElse: () => null,
      );
}
