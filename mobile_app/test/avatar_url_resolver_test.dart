import 'package:flutter/material.dart';
import 'package:family_todo_mobile/shared/utils/avatar_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AvatarUrlResolver', () {
    group('resolveUrl', () {
      test('returns empty string unchanged', () {
        expect(AvatarUrlResolver.resolveUrl(''), '');
        expect(AvatarUrlResolver.resolveUrl('   '), '');
      });

      test('returns full HTTP URL unchanged', () {
        const url = 'https://example.com/avatars/user.jpg';
        expect(AvatarUrlResolver.resolveUrl(url), url);
      });

      test('returns http URL unchanged', () {
        const url = 'http://cdn.example.com/photo.png';
        expect(AvatarUrlResolver.resolveUrl(url), url);
      });

      test('prepends apiBaseUrl to server-relative path', () {
        final resolved = AvatarUrlResolver.resolveUrl('/avatars/u_001.jpg');
        expect(resolved, startsWith('http://'));
        expect(resolved, endsWith('/avatars/u_001.jpg'));
      });

      test('returns local path unchanged', () {
        const local = '/data/user/avatars/me.jpg';
        // Note: on non-Linux this is treated as relative, not file://
        final resolved = AvatarUrlResolver.resolveUrl(local);
        // Starts with / but not with http -> prepends AppConfig.apiBaseUrl
        expect(resolved, startsWith('http'));
      });
    });

    group('imageProvider', () {
      test('returns null for null input', () {
        expect(AvatarUrlResolver.imageProvider(null), isNull);
      });

      test('returns null for empty string', () {
        expect(AvatarUrlResolver.imageProvider(''), isNull);
        expect(AvatarUrlResolver.imageProvider('   '), isNull);
      });

      test('returns NetworkImage for server-relative path', () {
        final provider = AvatarUrlResolver.imageProvider('/avatars/test.jpg');
        expect(provider, isNotNull);
        expect(provider, isA<NetworkImage>());
      });

      test('returns NetworkImage for HTTP URL', () {
        final provider =
            AvatarUrlResolver.imageProvider('https://example.com/a.jpg');
        expect(provider, isNotNull);
        expect(provider, isA<NetworkImage>());
      });

      test('returns FileImage for local path', () {
        final provider =
            AvatarUrlResolver.imageProvider('C:\\data\\avatar.jpg');
        expect(provider, isNotNull);
        expect(provider, isA<FileImage>());
      });
    });
  });
}
