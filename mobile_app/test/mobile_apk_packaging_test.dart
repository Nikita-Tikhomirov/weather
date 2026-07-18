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

    expect(workflow, contains('kwork-lead-funnel.apk'));
    expect(workflow, contains('APPLICATION_ID: com.example.family_todo_mobile.installable'));
    expect(workflow, contains('APP_LABEL: Kwork Lead Funnel'));
    expect(workflow, contains('Verify package identifier'));
    expect(workflow, contains("package: name='"));
    expect(workflow, contains('LEAD_FUNNEL_KEYSTORE_BASE64'));
    expect(workflow, contains('Restore lead app signing key'));
    expect(workflow, contains('/tmp/apk-artifacts'));
    expect(
      workflow,
      contains('mkdir -p /tmp/apk-artifacts'),
    );
  });

  test('mobile release workflow does not accept generated fallback keys', () {
    final workflow = mobileApkWorkflowSource();

    expect(workflow, isNot(contains('Generating fallback release keystore')));
    expect(workflow, isNot(contains('Using cached fallback release keystore')));
    expect(workflow, contains('LEAD_FUNNEL_KEYSTORE_BASE64'));
    expect(workflow, contains('updateable Kwork Lead Funnel APK'));
  });
}
