import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import 'chat_call_helpers.dart';

class ChatCallBubble extends StatelessWidget {
  const ChatCallBubble({
    super.key,
    required this.message,
    required this.mine,
  });

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final meta = message.imageMeta;
    final status = chatCallStatus(meta);
    final type = chatCallType(meta);
    final durationSeconds = chatCallDurationSeconds(meta);
    final isMissed = status == 'missed';
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isMissed ? colorScheme.error : colorScheme.primary;
    final title = localizedChatCallTitle(
      AppLocalizations.of(context),
      status: status,
      callType: type,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          isMissed
              ? Icons.call_missed
              : (type == 'video' ? Icons.videocam : Icons.call),
          size: 22,
          color: accent,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (!isMissed && durationSeconds > 0) ...[
                const SizedBox(height: 2),
                Text(
                  formatChatCallDuration(durationSeconds),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
