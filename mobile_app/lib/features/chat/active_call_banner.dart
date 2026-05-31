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
