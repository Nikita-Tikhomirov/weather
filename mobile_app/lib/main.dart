import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/family_todo_app.dart';
import 'services/fcm_service.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        // In release mode, also log to an external service if available.
        if (kReleaseMode) {
          debugPrint('[FATAL] Flutter error: ${details.exception}');
          if (details.stack != null) {
            debugPrint('[FATAL] Stack: ${details.stack}');
          }
        }
      };

      // Custom error widget shown in release builds when a widget build fails.
      ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
        final String message =
            errorDetails.exceptionAsString().isNotEmpty
                ? errorDetails.exceptionAsString()
                : 'Something went wrong';
        return Material(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 48,
                      color: Colors.orange),
                  const SizedBox(height: 12),
                  Text('Something went wrong',
                      style: Theme.of(ErrorWidget._context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(message,
                      style: Theme.of(ErrorWidget._context).textTheme.bodySmall,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      };

      runApp(const FamilyTodoApp());
    },
    (Object error, StackTrace stack) {
      debugPrint('[FATAL] Uncaught top-level error: $error');
      debugPrint('[FATAL] Stack: $stack');
      // In a real app, send this to a crash reporting service.
    },
  );
}
