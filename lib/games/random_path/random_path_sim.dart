import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import 'random_path_config.dart';

/// Nothing happens for five seconds, and then everybody wins.
///
/// A game with no game in it, on purpose. What it exercises is the *board*: a
/// path that is laid out differently every round, which is the part worth
/// looking at while it is on the table. Keeping the rules empty means anything
/// that goes wrong is the arrangement's fault and not a rule's.
class RandomPathSim implements GameSim {
  RandomPathSim(this.context);

  final BoardContext context;

  double _elapsed = 0;

  bool get _over => _elapsed >= RandomPathConfig.roundSeconds;

  int get secondsLeft =>
      (RandomPathConfig.roundSeconds - _elapsed).ceil().clamp(0, 999);

  @override
  void step(double dt) {
    if (_over) return;
    _elapsed += dt;
  }

  @override
  void onTouch(TouchEvent touch) {}

  /// Nothing to draw, so nothing to interpolate.
  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => {
    // Whole seconds, not the raw clock: shared state is diffed every tick and a
    // value that always differs is a packet sixty times a second.
    'secondsLeft': secondsLeft,
    'over': _over,
  };

  @override
  GameOutcome? get outcome => _over
      ? const GameOutcome.won(summary: 'the path held together')
      : null;

  @override
  void reset() => _elapsed = 0;

  @override
  void dispose() {}
}
