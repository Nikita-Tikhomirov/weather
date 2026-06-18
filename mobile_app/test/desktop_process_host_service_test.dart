import 'package:family_todo_mobile/services/desktop_process_host_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('desktopPythonExecutableCandidates', () {
    test('uses environment-based Windows paths without hardcoded user profile',
        () {
      final candidates = desktopPythonExecutableCandidates(
        environment: const {
          'FAMILY_TODO_PYTHON': r'D:\tools\python.exe',
          'LOCALAPPDATA': r'C:\Users\nikita\AppData\Local',
        },
        isWindows: true,
      );

      expect(candidates.first, r'D:\tools\python.exe');
      expect(
        candidates,
        contains(
          r'C:\Users\nikita\AppData\Local\Programs\Python\Python311\python.exe',
        ),
      );
      expect(candidates, isNot(contains(startsWith(r'C:\Users\user\'))));
      expect(candidates.toSet(), hasLength(candidates.length));
    });

    test('keeps shell python fallback when no environment path is available',
        () {
      final candidates = desktopPythonExecutableCandidates(
        environment: const {},
        isWindows: false,
      );

      expect(candidates, ['python3', 'python']);
    });
  });
}
