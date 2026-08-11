import 'package:shared_preferences/shared_preferences.dart';

/// Where this phone stands on the NameDrop setting.
///
/// Three states rather than a bool, because "we have not asked yet" and "they
/// said no" have to be told apart. With a bool, a decline is indistinguishable
/// from a fresh install, so the only way to stop pestering somebody who said no
/// is to record their no as though they had complied — and then the one signal
/// that could correct a wrong answer has nothing to correct.
enum NameDropStatus {
  /// Nobody has been asked yet, or an answer has been withdrawn. The only
  /// state that shows the notice.
  waiting,

  /// They say the setting is off. Taken at face value: there is no API to
  /// check, and calling somebody a liar over a contact card is not the job.
  turnedOff,

  /// They would rather keep it on, and do not want to be asked again.
  declined,
}

/// Reads and writes [NameDropStatus], and nothing else.
///
/// Note what is **not** here: any notion of which devices the question applies
/// to. Defaulting the stored value per platform was tempting — an Android phone
/// could start life at [NameDropStatus.turnedOff] and never need a check at the
/// call site — but then the saved value asserts something false about the
/// device, and the first person to read it back is misled. The platform gate
/// lives in [NameDropSupport], where it can be answered honestly, and this
/// stays a plain three-valued preference that means the same thing everywhere.
class NameDropPref {
  const NameDropPref._();

  static const _key = 'nameDropStatus';

  /// Stored as a name rather than an index. Indices renumber themselves the
  /// first time somebody reorders the enum, and a preference that silently
  /// turns every decline into a compliance on the next release is a bad way to
  /// find that out.
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

  /// Anything unrecognised — nothing stored, a value from a build that spelled
  /// these differently, a preferences file somebody edited — reads as
  /// [NameDropStatus.waiting]. Asking once more is the harmless failure; the
  /// other two states both suppress the notice forever on a guess.
  static NameDropStatus _parse(String? raw) {
    for (final entry in _wire.entries) {
      if (entry.value == raw) return entry.key;
    }
    return NameDropStatus.waiting;
  }
}
