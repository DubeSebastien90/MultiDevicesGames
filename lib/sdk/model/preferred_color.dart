import 'package:shared_preferences/shared_preferences.dart';

import 'player_color.dart';

class PreferredColor {
  const PreferredColor._();

  static const _key = 'preferredColor';

  static Future<PlayerColor?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerPalette.byId(prefs.getString(_key));
  }

  static Future<void> save(PlayerColor color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, color.id);
  }
}
