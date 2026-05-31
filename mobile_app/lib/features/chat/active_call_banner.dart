import 'package:flutter/material.dart';

import '../../models/call_models.dart';
import '../../services/call_service.dart';

class ActiveCallOverlay extends StatelessWidget {
  const ActiveCallOverlay({
    super.key,
    required this.session,
    required this.state,
    required this.owner,
    required this.profileLabel,
    required this.onOpen,
    required this.onEnd,
    required this.onAccept,
    required this.child,
  });

  final CallSession? session;
  final CallState state;
  final String owner;
  final String Function(String profile) profileLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onEnd;
  final VoidCallback? onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final call = session;
    final isIncoming = call != null &&
        state == CallState.ringing &&
        call.calleeProfile == owner;
    if (isIncoming) {
      return Stack(
        children: [
          child,
          Positioned.fill(
            child: IncomingCallPrompt(
              session: call,
              owner: owner,
              profileLabel: profileLabel,
              onOpen: onOpen,
              onAccept: onAccept,
              onEnd: onEnd,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        ActiveCallBanner(
          session: session,
          state: state,
          owner: owner,
          profileLabel: profileLabel,
          onOpen: onOpen,
          onEnd: onEnd,
          onAccept: onAccept,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class IncomingCallPrompt extends StatelessWidget {
  const IncomingCallPrompt({
    super.key,
    required this.session,
    required this.owner,
    required this.profileLabel,
    required this.onOpen,
    required this.onEnd,
    required this.onAccept,
  });

  final CallSession session;
  final String owner;
  final String Function(String profile) profileLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onEnd;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final peerProfile = session.callerProfile == owner
        ? session.calleeProfile
        : session.callerProfile;
    final isVideo = session.callType == 'video';
    final callKind = isVideo ? 'видеозвонок' : 'аудиозвонок';
    final backgroundColor = isVideo ? Colors.black : const Color(0xFF0D47A1);
    final theme = Theme.of(context);

    return Material(
      color: backgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  session.callType == 'video' ? Icons.videocam : Icons.call,
                  color: Colors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Входящий $callKind',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ) ??
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                profileLabel(peerProfile),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                    ) ??
                    const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onEnd,
                      icon: const Icon(Icons.call_end),
                      label: const Text('Отклонить'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.call),
                      label: const Text('Принять'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onOpen,
                child: const Text('Открыть экран звонка'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActiveCallBanner extends StatelessWidget {
  const ActiveCallBanner({
    super.key,
    required this.session,
    required this.state,
    required this.owner,
    required this.profileLabel,
    required this.onOpen,
    required this.onEnd,
    required this.onAccept,
  });

  final CallSession? session;
  final CallState state;
  final String owner;
  final String Function(String profile) profileLabel;
  final VoidCallback? onOpen;
  final VoidCallback? onEnd;
  final VoidCallback? onAccept;

  bool get _isVisible =>
      session != null && state != CallState.idle && state != CallState.ended;

  bool get _isIncoming =>
      session != null &&
      state == CallState.ringing &&
      session!.calleeProfile == owner;

  @override
  Widget build(BuildContext context) {
    final call = session;
    if (!_isVisible || call == null) return const SizedBox.shrink();

    final peerProfile =
        call.callerProfile == owner ? call.calleeProfile : call.callerProfile;
    final callKind = call.callType == 'video' ? 'видеозвонок' : 'аудиозвонок';
    final title = _isIncoming ? 'Входящий $callKind' : 'Идет $callKind';
    final theme = Theme.of(context);

    return Material(
      color: _isIncoming ? const Color(0xFF1B5E20) : const Color(0xFF263238),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                call.callType == 'video' ? Icons.videocam : Icons.call,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ) ??
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        profileLabel(peerProfile),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ) ??
                            const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isIncoming && onAccept != null) ...[
                IconButton.filled(
                  tooltip: 'Принять',
                  onPressed: onAccept,
                  icon: const Icon(Icons.call),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              TextButton(
                onPressed: onOpen,
                child: Text(
                  _isIncoming ? 'Открыть' : 'Вернуться',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              if (onEnd != null)
                IconButton(
                  tooltip: _isIncoming ? 'Отклонить' : 'Завершить',
                  onPressed: onEnd,
                  icon: const Icon(Icons.call_end),
                  color: const Color(0xFFFFCDD2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
