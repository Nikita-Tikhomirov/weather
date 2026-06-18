import 'package:family_todo_mobile/features/chat/chat_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saves the currently visible photo and closes after success',
      (tester) async {
    var savedUrl = '';
    var savedCallbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showChatPhotoViewer(
                    context: context,
                    urls: const [
                      'https://example.invalid/first.jpg',
                      'https://example.invalid/second.jpg',
                    ],
                    initialIndex: 1,
                    onSaveImage: (url) async {
                      savedUrl = url;
                      return true;
                    },
                    onImageSaved: () {
                      savedCallbackCalled = true;
                    },
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(savedUrl, 'https://example.invalid/second.jpg');
    expect(savedCallbackCalled, isTrue);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('keeps the viewer open when saving fails', (tester) async {
    var failedCallbackCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showChatPhotoViewer(
                    context: context,
                    urls: const ['https://example.invalid/photo.jpg'],
                    initialIndex: 0,
                    onSaveImage: (_) async => false,
                    onImageSaveFailed: () {
                      failedCallbackCalled = true;
                    },
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(failedCallbackCalled, isTrue);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
