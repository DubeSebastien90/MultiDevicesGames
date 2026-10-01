library;

import '../audio/sound_cue.dart';
import '../audio/sounds.dart';
import '../render/player_art.dart';
import 'player_character.dart';
import 'player_color.dart';

class Player {
  const Player({required this.phoneId, required this.color, this.label = ''});

  final String phoneId;

  final PlayerColor color;

  final String label;

  PlayerCharacter get character => Cast.of(color);

  String get title => '${color.name} ${character.name}';

  PlayerArt get topdown => PlayerArt.of(color, PlayerArtSlot.topdown);

  PlayerArt get face => PlayerArt.of(color, PlayerArtSlot.face);

  SoundCue get soundHappy => PlayerSounds.happy(color);

  SoundCue get soundSad => PlayerSounds.sad(color);

  @override
  bool operator ==(Object other) =>
      other is Player && other.phoneId == phoneId && other.color.id == color.id;

  @override
  int get hashCode => Object.hash(phoneId, color.id);

  @override
  String toString() => 'Player($phoneId/${color.id})';
}

class Roster {
  const Roster(this.players, {this.hostPhoneId});

  final List<Player> players;

  final String? hostPhoneId;

  static const empty = Roster(<Player>[]);

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

  Player? byColor(PlayerColor color) {
    for (final p in players) {
      if (p.color.id == color.id) return p;
    }
    return null;
  }

  Iterable<Player> others(String phoneId) =>
      players.where((p) => p.phoneId != phoneId);
}
