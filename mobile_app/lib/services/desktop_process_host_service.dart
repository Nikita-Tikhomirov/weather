import 'dart:async';
import 'dart:io';

enum DesktopHostStatus { stopped, running, error }

class DesktopHostState {
  const DesktopHostState({
    required this.status,
    required this.lastMessage,
  });

  final DesktopHostStatus status;
  final String lastMessage;
}

class DesktopProcessHostService {
  DesktopProcessHostService({
    required this.workingDirectory,
    required this.onVoiceState,
    required this.onBotState,
    required this.onLog,
  });

  final String workingDirectory;
  final void Function(DesktopHostState state) onVoiceState;
  final void Function(DesktopHostState state) onBotState;
  final void Function(String message, {bool isError}) onLog;

  Process? _voiceProcess;
  Process? _botProcess;

  Future<void> startVoice() async {
    if (_isRunning(_voiceProcess)) {
      onVoiceState(
        const DesktopHostState(
          status: DesktopHostStatus.running,
          lastMessage: 'voice already running',
        ),
      );
      return;
    }
    final result = await _startScript(['voice_trigger.py']);
    if (!result.ok) {
      onVoiceState(
        DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: result.message,
        ),
      );
      onLog(result.message, isError: true);
      return;
    }
    _voiceProcess = result.process!;
    onVoiceState(
      const DesktopHostState(
        status: DesktopHostStatus.running,
        lastMessage: 'voice running',
      ),
    );
    onLog('voice started');
    unawaited(_attachExitObserver(_voiceProcess!, isVoice: true));
  }

  Future<void> stopVoice() async {
    await _stopProcess(
      process: _voiceProcess,
      onStopped: () {
        _voiceProcess = null;
        onVoiceState(
          const DesktopHostState(
            status: DesktopHostStatus.stopped,
            lastMessage: 'voice stopped',
          ),
        );
        onLog('voice stopped');
      },
    );
  }

  Future<void> startBot() async {
    if (_isRunning(_botProcess)) {
      onBotState(
        const DesktopHostState(
          status: DesktopHostStatus.running,
          lastMessage: 'bot already running',
        ),
      );
      return;
    }
    final token = Platform.environment['TELEGRAM_BOT_TOKEN'] ?? '';
    if (token.trim().isEmpty) {
      const message = 'TELEGRAM_BOT_TOKEN is missing';
      onBotState(
        const DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: message,
        ),
      );
      onLog(message, isError: true);
      return;
    }
    final result = await _startScript(
      ['desktop_app.py', '--bot-only'],
      extraEnvironment: const {'TODO_BACKEND_SOURCE': 'telegram'},
    );
    if (!result.ok) {
      onBotState(
        DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: result.message,
        ),
      );
      onLog(result.message, isError: true);
      return;
    }
    _botProcess = result.process!;
    onBotState(
      const DesktopHostState(
        status: DesktopHostStatus.running,
        lastMessage: 'bot running',
      ),
    );
    onLog('bot started');
    unawaited(_attachExitObserver(_botProcess!, isVoice: false));
  }

  Future<void> stopBot() async {
    await _stopProcess(
      process: _botProcess,
      onStopped: () {
        _botProcess = null;
        onBotState(
          const DesktopHostState(
            status: DesktopHostStatus.stopped,
            lastMessage: 'bot stopped',
          ),
        );
        onLog('bot stopped');
      },
    );
  }

  Future<void> stopAll() async {
    await stopVoice();
    await stopBot();
  }

  bool _isRunning(Process? process) => process != null;

  Future<void> _attachExitObserver(
    Process process, {
    required bool isVoice,
  }) async {
    final code = await process.exitCode;
    if (isVoice && identical(process, _voiceProcess)) {
      _voiceProcess = null;
      if (code == 0) {
        onVoiceState(
          const DesktopHostState(
            status: DesktopHostStatus.stopped,
            lastMessage: 'voice exited',
          ),
        );
        onLog('voice exited');
      } else {
        onVoiceState(
          DesktopHostState(
            status: DesktopHostStatus.error,
            lastMessage: 'voice exited with code $code',
          ),
        );
        onLog('voice exited with code $code', isError: true);
      }
    }
    if (!isVoice && identical(process, _botProcess)) {
      _botProcess = null;
      if (code == 0) {
        onBotState(
          const DesktopHostState(
            status: DesktopHostStatus.stopped,
            lastMessage: 'bot exited',
          ),
        );
        onLog('bot exited');
      } else {
        onBotState(
          DesktopHostState(
            status: DesktopHostStatus.error,
            lastMessage: 'bot exited with code $code',
          ),
        );
        onLog('bot exited with code $code', isError: true);
      }
    }
  }

  Future<_StartResult> _startScript(
    List<String> args, {
    Map<String, String> extraEnvironment = const {},
  }) async {
    final candidates = <String>[
      'python',
      r'C:\Users\user\AppData\Local\Programs\Python\Python310\python.exe',
      r'C:\Users\user\AppData\Local\Programs\Python\Python311\python.exe',
    ];
    for (final executable in candidates) {
      try {
        final env = Map<String, String>.from(Platform.environment)
          ..addAll(extraEnvironment);
        final process = await Process.start(
          executable,
          args,
          workingDirectory: workingDirectory,
          environment: env,
          runInShell: true,
        );
        return _StartResult.ok(process);
      } catch (_) {
        continue;
      }
    }
    return const _StartResult.fail(
        'python is not available or script not found');
  }

  Future<void> _stopProcess({
    required Process? process,
    required VoidCallback onStopped,
  }) async {
    if (process == null) {
      onStopped();
      return;
    }
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    } finally {
      onStopped();
    }
  }
}

typedef VoidCallback = void Function();

class _StartResult {
  const _StartResult.ok(this.process)
      : ok = true,
        message = '';
  const _StartResult.fail(this.message)
      : ok = false,
        process = null;

  final bool ok;
  final Process? process;
  final String message;
}
