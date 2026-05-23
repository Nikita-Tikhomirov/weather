import os
os.chdir(r'C:\Users\user\Desktop\weather')
path = 'mobile_app/lib/features/home/home_page.dart'
with open(path, 'r', encoding='utf-8', newline='') as f:
    content = f.read()

# 1. Add part declaration
content = content.replace(
    "part 'projects_data.dart';",
    "part 'projects_data.dart';\npart 'calls_voice.dart';"
)

# 2. Find _handleIncomingCall
calls_start = content.find('_handleIncomingCall(CallSession session)')
if calls_start < 0:
    print('ERROR: _handleIncomingCall not found')
    exit(1)

# Go back to find the start of the method line
line_start = content.rfind('\n', 0, calls_start) + 1
calls_start = content.rfind('  void ', 0, calls_start)
if calls_start < 0:
    calls_start = line_start

# Find _retryPendingMessages after calls
retry_start = content.find('  Future<void> _retryPendingMessages(', calls_start)
if retry_start < 0:
    print('ERROR: _retryPendingMessages not found')
    exit(1)

calls_block = content[calls_start:retry_start]
content = content[:calls_start] + content[retry_start:]

# 3. Write calls_voice.dart
calls_file = '''part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Call handling & voice recording extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _CallsVoiceExtension on _HomePageState {
''' + calls_block + '''
}
'''

with open('mobile_app/lib/features/home/calls_voice.dart', 'w', encoding='utf-8', newline='') as f:
    f.write(calls_file)

# 4. Write updated home_page.dart
with open(path, 'w', encoding='utf-8', newline='') as f:
    f.write(content)

print('DONE')
print(f'Calls/voice block: {len(calls_block)} chars')
