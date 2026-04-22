import 'dart:async';
import 'dart:io';

enum DesktopHostStatus { stopped, running, error }

class DesktopHostState {
  const DesktopHostState({
    required this.status,
    required this.lastMessage,
    this.errorCode,
  });

  final DesktopHostStatus status;
  final String lastMessage;
  final String? errorCode;
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
          errorCode: 'invalid_token',
        ),
      );
      onLog('bot_auth_failed: $message', isError: true);
      return;
    }
    final probe = await _validateBotStartup();
    if (!probe.ok) {
      onBotState(
        DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: probe.message,
          errorCode: probe.errorCode,
        ),
      );
      final diagnostic = _diagnosticForBotErrorCode(probe.errorCode);
      onLog('$diagnostic: ${probe.message}', isError: true);
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
          errorCode: 'process_exit_nonzero',
        ),
      );
      onLog('process_exit_nonzero: ${result.message}', isError: true);
      return;
    }
    _botProcess = result.process!;
    final earlyExitCode = await _waitForEarlyExit(
      _botProcess!,
      const Duration(milliseconds: 900),
    );
    if (earlyExitCode != null) {
      _botProcess = null;
      final message = 'bot exited with code $earlyExitCode';
      onBotState(
        const DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: 'bot exited early',
          errorCode: 'process_exit_nonzero',
        ),
      );
      onLog('process_exit_nonzero: $message', isError: true);
      return;
    }
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
            errorCode: 'process_exit_nonzero',
          ),
        );
        onLog('process_exit_nonzero: bot exited with code $code',
            isError: true);
      }
    }
  }

  Future<int?> _waitForEarlyExit(Process process, Duration grace) async {
    try {
      final code = await process.exitCode.timeout(grace);
      return code;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<_ProbeResult> _validateBotStartup() async {
    final candidates = <String>[
      'python',
      r'C:\Users\user\AppData\Local\Programs\Python\Python310\python.exe',
      r'C:\Users\user\AppData\Local\Programs\Python\Python311\python.exe',
    ];
    for (final executable in candidates) {
      try {
        final env = Map<String, String>.from(Platform.environment);
        final result = await Process.run(
          executable,
          ['desktop_app.py', '--bot-validate'],
          workingDirectory: workingDirectory,
          environment: env,
          runInShell: true,
        );
        final output =
            '${result.stdout ?? ''}\n${result.stderr ?? ''}'.trim();
        if (result.exitCode == 0) {
          return const _ProbeResult.ok();
        }
        final match = RegExp(r'BOT_VALIDATE_FAIL:([a-z_]+):(.*)')
            .firstMatch(output.replaceAll('\r', ''));
        if (match != null) {
          final code = (match.group(1) ?? 'process_exit_nonzero').trim();
          final message = (match.group(2) ?? '').trim();
          return _ProbeResult.fail(
            errorCode: code.isEmpty ? 'process_exit_nonzero' : code,
            message: message.isEmpty
                ? 'bot validation failed'
                : message,
          );
        }
        return _ProbeResult.fail(
          errorCode: 'process_exit_nonzero',
          message: output.isEmpty
              ? 'bot validation failed'
              : output,
        );
      } catch (_) {
        continue;
      }
    }
    return const _ProbeResult.fail(
      errorCode: 'process_exit_nonzero',
      message: 'python is not available or validation script not found',
    );
  }

  String _diagnosticForBotErrorCode(String code) {
    if (code == 'invalid_token') {
      return 'bot_auth_failed';
    }
    if (code == 'telegram_timeout' || code == 'network_unreachable') {
      return 'bot_network_timeout';
    }
    return 'bot_startup_failed';
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

class _ProbeResult {
  const _ProbeResult.ok()
      : ok = true,
        errorCode = 'ok',
        message = '';

  const _ProbeResult.fail({
    required this.errorCode,
    required this.message,
  }) : ok = false;

  final bool ok;
  final String errorCode;
  final String message;
}
