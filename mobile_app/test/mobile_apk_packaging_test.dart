import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String mobileApkWorkflowSource() {
  final candidates = [
    File('../.github/workflows/mobile-apk.yml'),
    File('.github/workflows/mobile-apk.yml'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  fail('mobile-apk.yml was not found in repo or isolated CI project');
}

void main() {
  test('Android packaging supports a no-conflict install variant', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final googleServices =
        jsonDecode(File('android/app/google-services.json').readAsStringSync())
            as Map<String, dynamic>;
    final workflow = mobileApkWorkflowSource();

    expect(buildGradle, contains('APPLICATION_ID'));
    expect(buildGradle, contains('APP_LABEL'));
    expect(buildGradle, contains('applicationId appApplicationId'));
    expect(manifest, contains('android:label="@string/app_name"'));

    final clients = (googleServices['client'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (client) => (((client['client_info'] as Map)['android_client_info']
                  as Map)['package_name'])
              .toString(),
        )
        .toSet();
    expect(clients, contains('com.example.family_todo_mobile'));
    expect(clients, contains('com.example.family_todo_mobile.installable'));

    expect(workflow, contains('family-todo-installable.apk'));
    expect(workflow, contains('--android-project-arg=APPLICATION_ID='));
    expect(workflow, contains('--android-project-arg=APP_LABEL='));
    expect(workflow, contains('Verify APK package ids'));
    expect(workflow, contains("package: name='"));
    expect(workflow, contains('INSTALLABLE_APK_PATH'));
    expect(workflow, contains('Detected installable APK candidates'));
    expect(
      workflow,
      contains('mkdir -p /tmp/family_todo_mobile/build/app/outputs/flutter-apk'),
    );
    expect(workflow, contains('APPLICATION_ID: com.example.family_todo_mobile'));
    expect(
      workflow,
      contains('APPLICATION_ID: com.example.family_todo_mobile.installable'),
    );
    expect(workflow, contains('APP_LABEL: Family Todo New'));
  });

  test('mobile release workflow does not accept generated fallback keys', () {
    final workflow = mobileApkWorkflowSource();

    expect(workflow, contains('SIGNING_KEY_SOURCE=secrets'));
    expect(workflow, isNot(contains('Generating fallback release keystore')));
    expect(workflow, contains('Using cached fallback release keystore'));
    expect(workflow, contains('RELEASE_KEYSTORE_BASE64 is required'));
    expect(workflow, contains('Refusing to generate a new signing key'));
  });
}
