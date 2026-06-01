import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat attachment tolerates legacy list image metadata', () {
    final attachment = ChatAttachment.fromJson(const {
      'kind': 'image',
      'asset_url': '/chat_uploads/photo.jpg',
      'image_meta': [],
      'sort_order': 0,
    });

    expect(attachment.kind, 'image');
    expect(attachment.assetUrl, '/chat_uploads/photo.jpg');
    expect(attachment.imageMeta, isEmpty);
    expect(attachment.sortOrder, 0);
  });
}
