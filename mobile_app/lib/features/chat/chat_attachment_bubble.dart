import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a document/file attachment bubble.
class ChatAttachmentBubble extends StatelessWidget {
  const ChatAttachmentBubble({
    super.key,
    required this.fileName,
    required this.fileUrl,
    required this.mine,
    this.sizeBytes = 0,
  });

  final String fileName;
  final String fileUrl;
  final bool mine;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = fileName.contains('.') ? fileName.split('.').last : '';
    final icon = _iconForExtension(ext);
    final displayName = fileName.isNotEmpty ? fileName : 'Документ';
    final sizeText = _formatFileSize(sizeBytes);
    return GestureDetector(
      onTap: () async {
        if (fileUrl.isEmpty) return;
        final uri = Uri.tryParse(fileUrl);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('[chat] launchUrl error: $e');
        }
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
            Icon(icon, size: 36, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sizeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.download, size: 24, color: cs.primary),
          ],
        ),
      ),
    );
  }

  static IconData _iconForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return Icons.audiotrack;
      case 'mp4':
      case 'mov':
      case 'webm':
      case 'mkv':
        return Icons.videocam;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image;
      case 'txt':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}
