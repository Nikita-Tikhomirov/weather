import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Renders audio message content.
class ChatAudioBubble extends StatelessWidget {
  const ChatAudioBubble({
    super.key,
    required this.audioUrl,
    required this.text,
    required this.mine,
  });

  final String audioUrl;
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        const ch = MethodChannel('family_todo_mobile/voice');
        ch.invokeMethod('playVoice', {'url': audioUrl});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.audiotrack,
              size: 28,
              color: mine ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.isNotEmpty
                    ? text
                    : AppLocalizations.of(context)?.audioMessage ?? 'Audio',
                style: TextStyle(
                  fontSize: 14,
                  color: mine ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
