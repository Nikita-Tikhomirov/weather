import 'package:family_todo_mobile/features/home/desktop_shell_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('falls back to English desktop shell labels', () {
    const labels = DesktopShellLabels(null);

    expect(labels.tasks, 'Tasks');
    expect(labels.calendar, 'Calendar');
    expect(labels.messenger, 'Messenger');
    expect(labels.light, 'Light');
    expect(labels.dark, 'Dark');
    expect(labels.theme, 'Theme');
    expect(labels.voice, 'Voice');
    expect(labels.addTask, 'Add');
    expect(labels.sync, 'Sync');
    expect(labels.undo, 'Undo');
    expect(labels.administration, 'Administration');
    expect(labels.taskTitle('2026-06-13'), 'Tasks - 2026-06-13');
  });
}
