import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Which of two groups this device's owner falls into, and nothing finer.
///
/// The app broadcasts a player name and a game name over the local network, in
/// clear, to anything listening — that is how a phone finds a table it is
/// allowed to sit at. A free text field feeding that is fine for an adult who
/// can weigh it, and is not fine for a nine-year-old who will type the name
/// their teacher calls them. So the two text fields are closed for children and
/// a name is issued instead, and this is the one bit of state that decides it.
///
/// Three values rather than a bool, for the same reason [NameDropStatus] has
/// three: "not asked yet" is a real state, and folding it into either answer
/// gets somebody the wrong treatment. A fresh install must be told apart from
/// an answered one, or the question either never gets asked or gets asked every
/// launch.
enum AgeBand {
  /// Nobody has answered yet. The only state that shows the question, and the
  /// only one that is never written to storage.
  unknown,

  /// Under the threshold. Names are issued, not typed.
  child,

  /// At or over it. The text fields behave as they always did.
  adult,
}

/// Turns a birth month into an [AgeBand], and remembers only which one.
///
/// **What is deliberately not stored: the date.** A birth date is the kind of
/// thing that is boring right up until the moment somebody has a reason to want
/// it, and it is worth exactly nothing to this app after the second it is
/// entered — every question the app will ever ask of it is answered by one bit.
/// So the date is a local variable that lives for the length of a button press,
/// and what lands on disk is the word `child` or the word `adult`.
class AgeGatePref {
  const AgeGatePref._();

  static const _key = 'ageBand';

  /// **Not shown to the user, anywhere, in any wording.** A screen that says
  /// "you must be 13" has told the reader precisely which answer to give, and
  /// every child who wants the text field back will give it. The question is
  /// asked plainly and the arithmetic happens where nobody can read it.
  static const _childUnder = 13;

  /// Nobody was born 120 years before opening a party game on a phone. Wide
  /// enough that it only ever catches a typo, which is all it is for.
  static const _maxYears = 120;

  /// Stored as a word rather than an enum index, so reordering the enum later
  /// cannot silently promote every child on every installed copy.
  static const _wire = {AgeBand.child: 'child', AgeBand.adult: 'adult'};

  static Future<AgeBand> load() async {
    final prefs = await SharedPreferences.getInstance();
    return parse(prefs.getString(_key));
  }

  /// Writes [band], unless that would undo a `child`.
  ///
  /// The ratchet is the point. Without it, the cheapest bypass in the app is to
  /// reach the question a second time and answer it differently — and any code
  /// added later that reopens the screen, however well meant, becomes that
  /// second chance. Here, the escalation is refused at the one place that can
  /// see both the old value and the new, so no caller can get it wrong.
  ///
  /// [AgeBand.unknown] is not a thing that can be saved. It means "not asked",
  /// and a stored "not asked" is just an unstored one with extra steps.
  static Future<void> save(AgeBand band) async {
    if (band == AgeBand.unknown) return;
    final prefs = await SharedPreferences.getInstance();
    if (parse(prefs.getString(_key)) == AgeBand.child) return;
    await prefs.setString(_key, _wire[band]!);
  }

  /// Debug builds only: forgets the answer, so the gate asks again on the next
  /// launch.
  ///
  /// Deliberately not routed through [save]. The ratchet there exists to make
  /// precisely this impossible, and the moment a second path can undo a
  /// `child` the ratchet is decoration. So this one removes the key outright
  /// and refuses to run at all outside a debug build — the guard lives here,
  /// next to the thing it protects, rather than in whichever screen happens to
  /// offer the button.
  static Future<void> debugForget() async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Anything unrecognised reads as [AgeBand.unknown] — nothing stored, a value
  /// from a build that spelled these differently, a preferences file somebody
  /// went at with a text editor. Asking again is the harmless failure; guessing
  /// `adult` opens a text field on a wrong guess.
  static AgeBand parse(String? raw) {
    for (final entry in _wire.entries) {
      if (entry.value == raw) return entry.key;
    }
    return AgeBand.unknown;
  }

  /// The band for somebody born in [birthMonth] of [birthYear], as of [now].
  ///
  /// Month precision, no day, because a day would be a third field to fill in
  /// and it buys one thing: certainty during the birthday month itself. That
  /// month is resolved by assuming the birthday has **not** happened yet, which
  /// rounds the answer down and lands anyone genuinely ambiguous in [child].
  /// Being handed a generated name a few weeks early costs a player nothing;
  /// the error in the other direction is the one this whole file exists to
  /// prevent.
  static AgeBand classify({
    required int birthYear,
    required int birthMonth,
    required DateTime now,
  }) {
    var years = now.year - birthYear;
    if (now.month <= birthMonth) years -= 1;
    return years < _childUnder ? AgeBand.child : AgeBand.adult;
  }

  /// Whether this could be a date a living person was born on.
  ///
  /// Only a typo filter. It rejects the future and the absurdly distant past,
  /// and it is careful to reject them for reasons that have nothing to do with
  /// [_childUnder] — a validator that only complains about young answers is the
  /// threshold, announced.
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
