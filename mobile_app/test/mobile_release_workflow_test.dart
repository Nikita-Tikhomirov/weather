import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release workflow can publish the separately installable lead app', () {
    final workflowFile = [
      File('../.github/workflows/mobile-apk.yml'),
      File('.github/workflows/mobile-apk.yml'),
    ].firstWhere((file) => file.existsSync());
    final workflow = workflowFile.readAsStringSync();

    expect(workflow, contains('LEAD_FUNNEL_KEYSTORE_BASE64'));
    expect(workflow, contains('com.example.family_todo_mobile.installable'));
    expect(workflow, contains('kwork-lead-funnel.apk'));
    expect(
      workflow,
      contains(
        r'cp -a mobile_app/android/app/src/main/res/. "$APP_DIR/android/app/src/main/res/"',
      ),
    );
    expect(
      workflow,
      contains(
        r'cp -a mobile_app/android/app/src/main/kotlin/. "$APP_DIR/android/app/src/main/kotlin/"',
      ),
    );
    expect(workflow, isNot(contains('family-todo-release.apk')));
  });
}
