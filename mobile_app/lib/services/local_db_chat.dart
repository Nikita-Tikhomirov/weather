part of 'local_db.dart';

// ── Shared helpers used by LocalDbChat extension ────────────────

List<String> _decodeStringList(String raw) {
  if (raw.isEmpty || raw == '[]') return [];
  try {
    return (jsonDecode(raw) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

Map<String, dynamic>? _decodeMap(String raw) {
  if (raw.isEmpty || raw == '{}') return null;
  try {
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

List<dynamic> _decodeDynamicList(String raw) {
  if (raw.isEmpty || raw == '[]') return [];
  try {
    return jsonDecode(raw) as List<dynamic>;
  } catch (_) {
    return [];
  }
}
