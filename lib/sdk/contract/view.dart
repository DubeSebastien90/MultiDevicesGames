import 'package:flutter/widgets.dart';

import '../audio/game_audio.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import '../model/player.dart';
import '../render/player_animation.dart';
import '../model/world_rect.dart';
import '../score/scoreboard.dart';
import 'entity.dart';

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

  final Map<String, RenderEntity> entities;

  final Map<String, Object?> sharedState;
  final ScoreView scores;

  final double timeMs;

  final double dt;

  final PhoneLayout me;

  final WorldRect board;
  final CoverageMap coverage;

  WorldRect get visible => me.viewport;

  double get onePixel => 1 / me.logicalPxPerWorldUnit;

  Iterable<RenderEntity> ofKind(String kind) =>
      entities.values.where((e) => e.kind == kind);

  RenderEntity? byId(String id) => entities[id];
}

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

  final Roster roster;

  final PlayerAnimations characters;

  final LocalAudio audio;

  Player? get me => roster.byPhone(phoneId);
}

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

abstract class GameView {
  Future<void> load() async {}

  void render(Canvas canvas, Frame frame);

  Widget? buildHud(BuildContext context, HudFrame frame) => null;

  void dispose() {}
}
