import 'package:family_todo_mobile/features/home/home_dashboard_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes English dashboard fallback labels', () {
    const labels = HomeDashboardLabels();

    expect(labels.allTasks, 'All tasks');
    expect(labels.manageProjectsAndGroups, 'Manage projects and groups');
  });
}
