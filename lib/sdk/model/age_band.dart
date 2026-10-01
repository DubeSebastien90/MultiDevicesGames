import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

enum AgeBand { unknown, child, adult }

class AgeGatePref {
  const AgeGatePref._();

  static const _key = 'ageBand';

  static const _childUnder = 13;

  static const _maxYears = 120;

  static const _wire = {AgeBand.child: 'child', AgeBand.adult: 'adult'};

  static Future<AgeBand> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(_key));
  }

  static Future<void> save(AgeBand band) async {
    if (band == AgeBand.unknown) return;
    final prefs = await SharedPreferences.getInstance();
    if (parse(prefs.getString(_key)) == AgeBand.child) return;
    await prefs.setString(_key, _wire[band]!);
  }

  static Future<void> debugForget() async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static AgeBand parse(String? raw) {
    for (final entry in _wire.entries) {
      if (entry.value == raw) return entry.key;
    }
    return AgeBand.unknown;
  }

  static AgeBand classify({
    required int birthYear,
    required int birthMonth,
    required DateTime now,
  }) {
    var years = now.year - birthYear;
    if (now.month <= birthMonth) years -= 1;
    return years < _childUnder ? AgeBand.child : AgeBand.adult;
  }

  static bool isPlausible({
    required int birthYear,
    required int birthMonth,
    required DateTime now,
  }) {
    if (birthMonth < 1 || birthMonth > 12) return false;
    if (birthYear > now.year) return false;
    if (birthYear == now.year && birthMonth > now.month) return false;
    return birthYear >= now.year - _maxYears;
  }
}
