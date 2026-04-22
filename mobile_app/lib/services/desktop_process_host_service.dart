import 'dart:async';
import 'dart:convert';
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
  final Map<Process, _ProcessDiagnostics> _diagnosticsByProcess =
      <Process, _ProcessDiagnostics>{};

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
          errorCode: 'process_exit_nonzero',
        ),
      );
      onLog(result.message, isError: true);
      return;
    }
    final process = result.process!;
    _diagnosticsByProcess[process] = _ProcessDiagnostics();
    _attachProcessLogs(process: process, isBot: false);

    final startup = await _waitForStartup(process);
    if (!startup.running) {
      _voiceProcess = null;
      onVoiceState(
        DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: startup.message,
          errorCode: startup.errorCode,
        ),
      );
      onLog(startup.message, isError: true);
      return;
    }

    _voiceProcess = process;
    onVoiceState(
      const DesktopHostState(
        status: DesktopHostStatus.running,
        lastMessage: 'voice running',
      ),
    );
    onLog('voice started');
    unawaited(_attachExitObserver(process, isVoice: true));
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
          errorCode: 'process_exit_nonzero',
        ),
      );
      onLog(result.message, isError: true);
      return;
    }

    final process = result.process!;
    _diagnosticsByProcess[process] = _ProcessDiagnostics();
    _attachProcessLogs(process: process, isBot: true);

    final startup = await _waitForStartup(process);
    if (!startup.running) {
      _botProcess = null;
      onBotState(
        DesktopHostState(
          status: DesktopHostStatus.error,
          lastMessage: startup.message,
          errorCode: startup.errorCode,
        ),
      );
      onLog(startup.message, isError: true);
      return;
    }

    _botProcess = process;
    onBotState(
      const DesktopHostState(
        status: DesktopHostStatus.running,
        lastMessage: 'bot running',
      ),
    );
    onLog('bot started');
    unawaited(_attachExitObserver(process, isVoice: false));
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

  void _attachProcessLogs({required Process process, required bool isBot}) {
    final diagnostics = _diagnosticsByProcess[process];
    if (diagnostics == null) {
      return;
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (isBot) {
        _captureBotDiagnostic(diagnostics, trimmed);
      }
      onLog(trimmed);
    });

    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        return;
      }
      diagnostics.lastErrorLine = trimmed;
      if (isBot) {
        _captureBotDiagnostic(diagnostics, trimmed);
      }
      onLog(trimmed, isError: true);
    });
  }

  void _captureBotDiagnostic(_ProcessDiagnostics diagnostics, String line) {
    if (!line.startsWith('BOT_START_ERROR:')) {
      return;
    }
    final parts = line.split(':');
    if (parts.length < 3) {
      return;
    }
    diagnostics.botErrorCode = parts[1].trim();
    diagnostics.botErrorMessage = parts.sublist(2).join(':').trim();
  }

  Future<_StartupResult> _waitForStartup(Process process) async {
    try {
      final exit = await process.exitCode.timeout(
        const Duration(milliseconds: 1400),
      );
      final diagnostics = _diagnosticsByProcess[process];
      if (exit == 0) {
        return const _StartupResult(
          running: false,
          errorCode: 'process_exit_nonzero',
          message: 'Process exited immediately with code 0',
        );
      }
      final code = diagnostics?.botErrorCode ?? 'process_exit_nonzero';
      final message = diagnostics?.botErrorMessage ??
          diagnostics?.lastErrorLine ??
          'Process exited with code $exit';
      return _StartupResult(
        running: false,
        errorCode: code,
        message: message,
      );
    } on TimeoutException {
      return const _StartupResult(
        running: true,
        errorCode: null,
        message: '',
      );
    }
  }

  Future<void> _attachExitObserver(
    Process process, {
    required bool isVoice,
  }) async {
    final code = await process.exitCode;
    final diagnostics = _diagnosticsByProcess.remove(process);
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
            lastMessage:
                diagnostics?.lastErrorLine ?? 'voice exited with code $code',
            errorCode: 'process_exit_nonzero',
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
            lastMessage: diagnostics?.botErrorMessage ??
                diagnostics?.lastErrorLine ??
                'bot exited with code $code',
            errorCode: diagnostics?.botErrorCode ?? 'process_exit_nonzero',
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
      'python is not available or script not found',
    );
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
      _diagnosticsByProcess.remove(process);
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

class _StartupResult {
  const _StartupResult({
    required this.running,
    required this.errorCode,
    required this.message,
  });

  final bool running;
  final String? errorCode;
  final String message;
}

class _ProcessDiagnostics {
  String? lastErrorLine;
  String? botErrorCode;
  String? botErrorMessage;
}
