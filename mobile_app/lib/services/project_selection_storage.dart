import 'package:shared_preferences/shared_preferences.dart';

abstract class ProjectSelectionStorage {
  Future<String> readLastProjectId(String ownerKey);

  Future<void> saveLastProjectId(String ownerKey, String projectId);

  Future<void> clearLastProjectId(String ownerKey);
}

class SharedPreferencesProjectSelectionStorage
    implements ProjectSelectionStorage {
  const SharedPreferencesProjectSelectionStorage();

  static String _key(String ownerKey) => 'last_project_${ownerKey.trim()}';

  @override
  Future<String> readLastProjectId(String ownerKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key(ownerKey))?.trim() ?? '';
  }

  @override
  Future<void> saveLastProjectId(String ownerKey, String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = projectId.trim();
    if (value.isEmpty) {
      await prefs.remove(_key(ownerKey));
      return;
    }
    await prefs.setString(_key(ownerKey), value);
  }

  @override
  Future<void> clearLastProjectId(String ownerKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(ownerKey));
  }
}
