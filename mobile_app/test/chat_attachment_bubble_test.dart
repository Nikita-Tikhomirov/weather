import 'package:family_todo_mobile/features/chat/chat_attachment_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses English fallback labels and file size units', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Column(
              children: [
                ChatAttachmentBubble(
                  fileName: '',
                  fileUrl: '',
                  mine: false,
                  sizeBytes: 42,
                ),
                ChatAttachmentBubble(
                  fileName: 'notes.txt',
                  fileUrl: '',
                  mine: false,
                  sizeBytes: 1536,
                ),
                ChatAttachmentBubble(
                  fileName: 'archive.zip',
                  fileUrl: '',
                  mine: false,
                  sizeBytes: 1024 * 1024,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Document'), findsOneWidget);
    expect(find.text('42 B'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.text('1.0 MB'), findsOneWidget);
    expect(find.text('Документ'), findsNothing);
    expect(find.text('42 Б'), findsNothing);
    expect(find.text('1.5 КБ'), findsNothing);
    expect(find.text('1.0 МБ'), findsNothing);
  });
}
