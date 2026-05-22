import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/family_todo_app.dart';
import 'services/fcm_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const FamilyTodoApp());
}
