import 'package:shared_preferences/shared_preferences.dart';

import 'player_color.dart';

/// The colour this phone last chose, kept between runs and between tables.
///
/// Somebody who is always Red should not have to be Red again in every lobby.
/// The phone remembers, not the host: a host only ever meets a phone for one
/// session, and the person holding it is the one with the habit. The phone
/// offers it when it joins and the host seats it there if nobody has it yet.
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
