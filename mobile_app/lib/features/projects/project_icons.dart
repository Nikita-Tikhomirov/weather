import 'package:flutter/material.dart';

IconData projectIcon(String icon) {
  switch (icon) {
    case 'code':
      return Icons.code;
    case 'folder':
      return Icons.folder;
    case 'terminal':
    default:
      return Icons.terminal;
  }
}
