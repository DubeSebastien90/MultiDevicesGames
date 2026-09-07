import 'package:flutter/widgets.dart';

import '../audio/game_audio.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import '../model/player.dart';
import '../render/player_animation.dart';
import '../model/world_rect.dart';
import '../score/scoreboard.dart';
import 'entity.dart';

/// One instant of the shared timeline, as this phone should draw it.
class Frame {
  const Frame({
    required this.entities,
    required this.sharedState,
    required this.scores,
    required this.timeMs,
    required this.dt,
    required this.me,
    required this.board,
    required this.coverage,
  });

  /// Interpolated to this instant. Every phone sampling the same [timeMs] gets
  /// the same answer, which is the entire trick.
  final Map<String, RenderEntity> entities;

  final Map<String, Object?> sharedState;
  final ScoreView scores;

  /// The host's timeline, identical on every phone. Use this for animation
  /// phase, never a local clock, or two screens will pulse out of step.
  final double timeMs;

  /// Local frame delta, for effects that do not have to agree across phones.
  final double dt;

  /// This phone's slice of the world.
  final PhoneLayout me;

  final WorldRect board;
  final CoverageMap coverage;

  /// What this screen can actually show — cull against it.
  WorldRect get visible => me.viewport;

  /// One physical pixel, in world units. Stroke widths want this.
  double get onePixel => 1 / me.logicalPxPerWorldUnit;

  /// Entities of one kind, for the usual `for (final ball in frame.ofKind(...))`.
  Iterable<RenderEntity> ofKind(String kind) =>
      entities.values.where((e) => e.kind == kind);

  RenderEntity? byId(String id) => entities[id];
}

/// What a view is handed when it is built.
class ViewContext {
  const ViewContext({
    required this.phoneId,
    required this.board,
    this.roster = Roster.empty,
    this.audio = const SilentLocalAudio(),
    this.characters = PlayerAnimations.none,
  });

  final String phoneId;
  final WorldRect board;

  /// Everyone in the round, in board order, with their colour, character, art
  /// and sounds.
  ///
  /// Here rather than on [Frame] because the roster is fixed for the round and
  /// a list that never changes has no business being rebuilt sixty times a
  /// second. A view that wants a player's picture reads it once, at build time.
  final Roster roster;

  /// Everyone's walking character, already loaded and already the right
  /// colour. Ask for one with `characters.of(player.color)`, tell it to
  /// [PlayerAnimation.start] or [PlayerAnimation.stop] from whatever the game
  /// knows about movement, and draw it.
  ///
  /// Owned by the platform and thrown away with the view, which is why a game
  /// never loads or disposes anything here. Defaults to
  /// [PlayerAnimations.none], the geometry from `PlayerArt` — so a view built
  /// in a test, or on a phone where the animation did not load, draws the same
  /// thing it always did.
  final PlayerAnimations characters;

  /// A sound on this phone alone. Nothing the table should hear goes through
  /// here — that is the sim's to decide.
  final LocalAudio audio;

  /// This phone's own player.
  ///
  /// Null only before anybody has been seated, which a running round cannot be.
  Player? get me => roster.byPhone(phoneId);
}

/// The slow-changing half of a frame, for a HUD.
///
/// Deliberately excludes entity transforms: a HUD is Flutter widgets, and
/// rebuilding widgets sixty times a second to follow a moving ball is how you
/// turn a smooth game into a stuttering one.
class HudFrame {
  const HudFrame({
    required this.phoneId,
    required this.sharedState,
    required this.scores,
  });

  final String phoneId;
  final Map<String, Object?> sharedState;
  final ScoreView scores;
}

/// The pixels. Runs on every phone.
///
/// The canvas arrives with the camera already applied: draw at world positions
/// and it lands correctly on whichever screen can see it.
///
/// [render] **must not mutate game state.** It runs on every device at each
/// device's own frame rate, and two phones that disagree about the world
/// produce exactly the artefact this project exists to avoid. The host's sim is
/// the only writer; a view is a pure function of its [Frame].
abstract class GameView {
  /// Sprites, fonts, audio. Awaited during the placement screen, so a game is
  /// ready by the time the first frame is asked for and never blocks on a
  /// decode mid-round.
  Future<void> load() async {}

  void render(Canvas canvas, Frame frame);

  /// An optional overlay — a score, a prompt, a button.
  ///
  /// Ordinary Flutter widgets, rebuilt only when [HudFrame] changes, so a HUD
  /// never touches the render loop. Null for no overlay, which is the default.
  Widget? buildHud(BuildContext context, HudFrame frame) => null;

  void dispose() {}
}
