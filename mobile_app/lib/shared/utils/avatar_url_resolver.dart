import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_config.dart';

/// Resolves avatar URLs that may be server-relative paths.
///
/// The backend returns avatar paths like `/avatars/u_001.jpg` without the
/// host.  This helper prepends [AppConfig.apiBaseUrl] when the value starts
/// with `/`, and returns the value unchanged otherwise (e.g. full HTTP URLs
/// or local `file://` paths).
class AvatarUrlResolver {
  AvatarUrlResolver._();

  /// Builds an [ImageProvider] suitable for [CircleAvatar] and similar
  /// widgets.
  ///
  /// Returns `null` when [value] is null, empty, or whitespace-only.
  static ImageProvider? imageProvider(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('/')) {
      return NetworkImage('${AppConfig.apiBaseUrl}$trimmed');
    }
    if (trimmed.startsWith('http')) {
      return NetworkImage(trimmed);
    }
    return FileImage(File(trimmed));
  }

  /// Resolves a raw path string to an absolute URL.
  ///
  /// Returns [value] unchanged if it already starts with `http` or is empty.
  /// Prepends [AppConfig.apiBaseUrl] when it starts with `/`.
  static String resolveUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.startsWith('http')) return trimmed;
    if (trimmed.startsWith('/')) return '${AppConfig.apiBaseUrl}$trimmed';
    return trimmed;
  }
}
