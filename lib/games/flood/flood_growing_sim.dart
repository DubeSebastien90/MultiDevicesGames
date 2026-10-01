import '../../sdk/contract/sim.dart';
import '../flood_common/flood_board.dart';
import '../flood_common/flood_config.dart';
import '../flood_common/flood_sim.dart';

class FloodGrowingSim extends FloodSim {
  FloodGrowingSim(BoardContext context)
    : super(context, FloodBoard.teamsFor(context));

  @override
  double pushFor(double atElapsed) {
    final t = atElapsed < 0 ? 0.0 : atElapsed;
    return FloodConfig.basePush * (1 + t / FloodGrowingConfig.rampWindow);
  }

  double get power => pushFor(roundElapsed) / FloodConfig.basePush;

  @override
  double get effectiveBoundary => boundary;

  @override
  Map<String, Object?> get extraState => {
    FloodState.power: (power * 20).roundToDouble() / 20,
  };
}
