import '../../sdk/contract/sim.dart';
import '../flood_common/flood_board.dart';
import '../flood_common/flood_config.dart';
import '../flood_common/flood_sim.dart';

/// Option A: every tap hits harder than the last.
///
/// One override on top of [FloodSim], which is the whole variant. The boundary
/// is read raw — the field never moves — and instead the push grows with the
/// clock, so a round that was a slow tug at ten seconds is a landslide at
/// thirty. That is also what stops a stalemate: both sides are getting stronger
/// together, so the first team to hold even a small edge converts it faster and
/// faster, and the round breaks open rather than grinding.
class FloodGrowingSim extends FloodSim {
  FloodGrowingSim(BoardContext context)
      : super(context, FloodBoard.teamsFor(context));

  /// `basePush * (1 + elapsed / rampWindow)` — doubled at one rampWindow,
  /// tripled at two.
  @override
  double pushFor(double atElapsed) {
    final t = atElapsed < 0 ? 0.0 : atElapsed;
    return FloodConfig.basePush * (1 + t / FloodGrowingConfig.rampWindow);
  }

  /// The current tap's strength as a multiple of [FloodConfig.basePush], for
  /// the view to show how hard the round is hitting.
  double get power => pushFor(roundElapsed) / FloodConfig.basePush;

  /// Raw. The field is fixed in this variant; only the taps change.
  @override
  double get effectiveBoundary => boundary;

  /// So the view can show how hard a tap is landing right now.
  ///
  /// Coarse on purpose. The ramp climbs continuously for the whole round, so
  /// this is the one value here that never settles — and `sharedState` is
  /// diffed and sent on change, so a finely-rounded ramp would still put a
  /// packet on the wire several times a second forever. A twentieth of the
  /// base push is far below what the foam it drives can show.
  @override
  Map<String, Object?> get extraState => {
    FloodState.power: (power * 20).roundToDouble() / 20,
  };
}
