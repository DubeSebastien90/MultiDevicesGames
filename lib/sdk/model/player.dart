/// Somebody at the table, with everything a game needs to show them.
///
/// The platform knew three separate things about a person — a `phoneId` for the
/// wire, a label for diagrams, and a [PlayerColor] for reading across a table —
/// and a game that wanted all three had to assemble them itself. Guac-a-Mole
/// did, by shipping a map of colours through `sharedState` and taking it apart
/// again in its view, with a comment apologising for it.
///
/// This is that assembly, done once, by the thing that already holds every
/// piece. It composes [PlayerColor] rather than replacing it: everything that
/// reads a swatch today keeps working, and the colour is still the only part
/// that crosses the wire.
///
/// A player is **immutable and per-round**. The roster is fixed once the board
/// is compiled, which is why it belongs on `ViewContext` and `BoardContext`
/// rather than on `Frame`: a list that never changes has no business being
/// rebuilt sixty times a second.
library;

import '../audio/sound_cue.dart';
import '../audio/sounds.dart';
import '../render/player_art.dart';
import 'player_character.dart';
import 'player_color.dart';

class Player {
  const Player({
    required this.phoneId,
    required this.color,
    this.label = '',
  });

  /// Which phone. What a touch arrives tagged with, and what the `Scoreboard`
  /// is keyed by — so this is the bridge from "this thing belongs to Green"
  /// back to a row of the standings.
  final String phoneId;

  /// Who they are, at a glance, from across a table.
  final PlayerColor color;

  /// The device's own name: 'Pixel 7'. For diagrams and debug panels, not for
  /// prompts — nobody at the table thinks of themselves as a Pixel 7.
  final String label;

  /// What they are: the Frog, the Crab. One per colour, so this needs no
  /// second choice in the lobby and no second thing for the host to make
  /// unique.
  PlayerCharacter get character => Cast.of(color);

  /// What to call them out loud: 'Green Frog'.
  ///
  /// Both halves, because either alone goes wrong at a real table. The colour
  /// alone is forgettable; the character alone stops being unique the moment
  /// somebody mishears it.
  String get title => '${color.name} ${character.name}';

  /// Seen from above — the piece on the board.
  ///
  /// Always paints something: the placeholder circle when there is no artwork
  /// or it has not finished loading. A game never writes a fallback and a round
  /// never waits for a picture.
  PlayerArt get topdown => PlayerArt.of(color, PlayerArtSlot.topdown);

  /// Seen from the side — a portrait, for a HUD or the results screen.
  PlayerArt get face => PlayerArt.of(color, PlayerArtSlot.face);

  SoundCue get soundHappy => PlayerSounds.happy(color);

  SoundCue get soundSad => PlayerSounds.sad(color);

  @override
  bool operator ==(Object other) =>
      other is Player &&
      other.phoneId == phoneId &&
      other.color.id == color.id;

  @override
  int get hashCode => Object.hash(phoneId, color.id);

  @override
  String toString() => 'Player($phoneId/${color.id})';
}

/// The people in a round, and the ways a game asks about them.
///
/// A list plus the two lookups every game writes for itself otherwise. Built
/// once when the board is compiled and handed to both sides of the contract, so
/// a sim and a view can never disagree about who is playing.
class Roster {
  const Roster(this.players, {this.hostPhoneId});

  /// In board order — the same order as the slices and the placement diagram.
  final List<Player> players;

  /// Whose phone is running the session.
  ///
  /// Platform knowledge that no game can work out for itself: board order is
  /// not join order, and the host's seat is not reliably the first of either
  /// once somebody reconnects. It is here because games *ask* — Slingshot fires
  /// the host's face at a tower — and the alternative is each of them guessing.
  final String? hostPhoneId;

  static const empty = Roster(<Player>[]);

  /// The player whose phone is the host, if they are seated.
  Player? get host => hostPhoneId == null ? null : byPhone(hostPhoneId!);

  int get length => players.length;
  bool get isEmpty => players.isEmpty;
  bool get isNotEmpty => players.isNotEmpty;

  Player? byPhone(String phoneId) {
    for (final p in players) {
      if (p.phoneId == phoneId) return p;
    }
    return null;
  }

  /// Whose colour is this? The inverse of [byPhone], and what a game that deals
  /// by colour needs to get back to a phone.
  Player? byColor(PlayerColor color) {
    for (final p in players) {
      if (p.color.id == color.id) return p;
    }
    return null;
  }

  /// Everyone else. For 'tell the other seven', which is otherwise a `where`
  /// with an easy mistake in it.
  Iterable<Player> others(String phoneId) =>
      players.where((p) => p.phoneId != phoneId);
}
