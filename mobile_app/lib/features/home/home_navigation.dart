part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Navigation section extracted from _HomePageState.
// Bottom navigation bar and floating action button for the mobile scaffold.
// ───────────────────────────────────────────────────────────────

extension _NavigationSection on _HomePageState {
  Widget buildNavigationBar(TaskStore store) {
    return ValueListenableBuilder<int>(
      valueListenable: store.pageIndex,
      builder: (context, page, _) {
        return NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (index) {
            store.setPage(index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.view_kanban_outlined),
              label: 'Задачи',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Календарь',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              label: 'Мессенджер',
            ),
          ],
        );
      },
    );
  }

  Widget buildFloatingActionButton(TaskStore store) {
    return ValueListenableBuilder<int>(
      valueListenable: store.pageIndex,
      builder: (context, page, _) {
        if (page != 0) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton.extended(
          onPressed: () => _openTaskEditor(store),
          icon: const Icon(Icons.add),
          label: const Text('Задача'),
        );
      },
    );
  }
}
