part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Navigation section extracted from _HomePageState.
// Bottom navigation bar and floating action button for the mobile scaffold.
// ───────────────────────────────────────────────────────────────

extension _NavigationSection on _HomePageState {
  Widget buildNavigationBar(TaskStore store) {
    return HomeNavigationBar(
      pageIndex: store.pageIndex,
      canUseTaskManager: _accessPolicy.canUseTaskManager,
      onPageSelected: store.setPage,
    );
  }

  Widget buildFloatingActionButton(TaskStore store) {
    return HomeTaskFloatingActionButton(
      pageIndex: store.pageIndex,
      canUseTaskManager: _accessPolicy.canUseTaskManager,
      onPressed: () => _openTaskEditor(store),
    );
  }
}
