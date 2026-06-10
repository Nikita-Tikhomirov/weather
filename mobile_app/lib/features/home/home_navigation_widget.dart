import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class HomeNavigationBar extends StatelessWidget {
  const HomeNavigationBar({
    super.key,
    required this.pageIndex,
    required this.canUseTaskManager,
    required this.onPageSelected,
  });

  final ValueListenable<int> pageIndex;
  final bool canUseTaskManager;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: pageIndex,
      builder: (context, page, _) {
        if (!canUseTaskManager) {
          return _MessengerOnlyNavigationBar(
            label: l10n.messengerTab,
            onSelected: () => onPageSelected(2),
          );
        }
        return NavigationBar(
          selectedIndex: page,
          onDestinationSelected: onPageSelected,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.view_kanban_outlined),
              label: l10n.tasksTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              label: l10n.calendarTab,
            ),
            NavigationDestination(
              icon: const Icon(Icons.forum_outlined),
              label: l10n.messengerTab,
            ),
          ],
        );
      },
    );
  }
}

class _MessengerOnlyNavigationBar extends StatelessWidget {
  const _MessengerOnlyNavigationBar({
    required this.label,
    required this.onSelected,
  });

  final String label;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomAppBar(
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onSelected,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.forum_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeTaskFloatingActionButton extends StatelessWidget {
  const HomeTaskFloatingActionButton({
    super.key,
    required this.pageIndex,
    required this.canUseTaskManager,
    required this.onPressed,
  });

  final ValueListenable<int> pageIndex;
  final bool canUseTaskManager;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<int>(
      valueListenable: pageIndex,
      builder: (context, page, _) {
        if (!canUseTaskManager || page != 0) {
          return const SizedBox.shrink();
        }
        return FloatingActionButton.extended(
          onPressed: onPressed,
          icon: const Icon(Icons.add),
          label: Text(l10n.addTask),
        );
      },
    );
  }
}
