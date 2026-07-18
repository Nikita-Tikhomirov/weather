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
  test('Android packaging publishes one stable Family Todo APK', () {
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
    expect(workflow, isNot(contains('family-todo-installable.apk')));
    expect(workflow, contains('--android-project-arg=APPLICATION_ID='));
    expect(workflow, contains('--android-project-arg=APP_LABEL='));
    expect(workflow, contains('Verify APK package id'));
    expect(workflow, contains("package: name='"));
    expect(workflow, contains('/tmp/family_todo_mobile/apk-artifacts'));
    expect(
      workflow,
      contains('mkdir -p /tmp/family_todo_mobile/apk-artifacts'),
    );
    expect(workflow, contains('APPLICATION_ID: com.example.family_todo_mobile'));
    expect(workflow, contains('APP_LABEL: Family Todo'));
  });

  test('mobile release workflow requires the stable signing key', () {
    final workflow = mobileApkWorkflowSource();

    expect(workflow, contains('Using stable release keystore from GitHub secrets'));
    expect(workflow, isNot(contains('Generating fallback release keystore')));
    expect(workflow, isNot(contains('Using cached fallback release keystore')));
    expect(workflow, contains('RELEASE_KEYSTORE_* secrets are required'));
    expect(workflow, isNot(contains('Refusing to generate a new signing key')));
  });
}
