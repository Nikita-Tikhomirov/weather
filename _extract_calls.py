import os
os.chdir(r'C:\Users\user\Desktop\weather')
path = 'mobile_app/lib/features/home/home_page.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add part declaration
content = content.replace(
    "part 'projects_data.dart';",
    "part 'projects_data.dart';\npart 'calls_voice.dart';"
)

# 2. Find and extract call/voice methods
# _handleIncomingCall starts the block
calls_start = content.find('  void _handleIncomingCall(CallSession session) {')
# _sendVoiceFile is in the block, them showSnack, then _retryPendingMessages
# Extract from _handleIncomingCall to before _retryPendingMessages
retry_start = content.find('  Future<void> _retryPendingMessages(', calls_start)
if calls_start >= 0 and retry_start > calls_start:
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

with open('mobile_app/lib/features/home/calls_voice.dart', 'w', encoding='utf-8') as f:
    f.write(calls_file)

# 4. Write updated home_page.dart
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('DONE')
print(f'Calls/voice block: {len(calls_block)} chars')
