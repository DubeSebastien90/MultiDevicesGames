import 'package:shared_preferences/shared_preferences.dart';

enum NameDropStatus { waiting, turnedOff, declined }

class NameDropPref {
  const NameDropPref._();

  static const _key = 'nameDropStatus';

  static const _wire = {
    NameDropStatus.waiting: 'waiting',
    NameDropStatus.turnedOff: 'turnedOff',
    NameDropStatus.declined: 'declined',
  };

  static Future<NameDropStatus> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _parse(prefs.getString(_key));
  }

  static Future<void> save(NameDropStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _wire[status]!);
  }

  static NameDropStatus _parse(String? raw) {
    for (final entry in _wire.entries) {
      if (entry.value == raw) return entry.key;
    }
    return NameDropStatus.waiting;
  }
}
