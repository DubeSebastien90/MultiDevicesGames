/// Wire protocol for the multiscreen platform.
///
/// Everything is JSON over a [Transport]. Nothing here names a game: the
/// platform ships transforms, and what they mean is the game's business on both
/// ends. That is the whole reason a new game needs no new message type.
library;

/// Client -> Host.
class ClientMsg {
  /// First message on a fresh connection: the join code and this build's
  /// catalog fingerprint. The host answers nothing else until both check out.
  static const join = 'join';
  static const calibration = 'calibration';

  /// 'I want to be Green.' A request, not a statement: only the host can know
  /// whether Green is still free, so the answer comes back in the next lobby
  /// broadcast rather than being assumed here.
  static const pickColor = 'pickColor';

  static const confirmPlacement = 'confirmPlacement';
  static const touch = 'touch';
  static const ping = 'ping';
  static const reset = 'reset';

  /// 'Something covered my screen for a moment, and it was not me leaving.'
  ///
  /// Carries `agoMs`: how long ago the interruption *started*, measured on the
  /// sender's own clock. Deliberately a duration and not a timestamp — the two
  /// phones share no clock, and the host only needs to know whether two of
  /// these began at the same moment, which arithmetic on elapsed time answers
  /// without anybody agreeing what time it is.
  ///
  /// One of these on its own means very little; see [HostMsg.nameDropSuspected].
  static const interrupted = 'interrupted';
}

/// Host -> Client.
class HostMsg {
  static const welcome = 'welcome';
  static const lobby = 'lobby';
  static const layout = 'layout';

  /// The game is starting: board, and every entity that exists right now.
  static const worldInit = 'worldInit';

  /// Entities that have just appeared, with their descriptors.
  static const spawn = 'spawn';

  /// Entities that have gone.
  static const despawn = 'despawn';

  static const start = 'start';

  /// The 60 Hz transform stream. The only interpolated message.
  static const state = 'state';

  /// The game's own slow-changing values, sent when they change.
  static const shared = 'shared';

  /// The session standings, sent when they change.
  static const scores = 'scores';

  /// The round ended.
  static const outcome = 'outcome';

  /// This phone has no place in the round on the table, and should wait for the
  /// next one.
  ///
  /// Sent to a phone that reconnects mid-round. It is a message rather than a
  /// phase in the lobby broadcast because it is about *one* phone: everybody
  /// else is playing, and the lobby broadcast says the same thing to all of
  /// them.
  static const sitOut = 'sitOut';

  /// 'You and the phone beside you were both interrupted at once, and your
  /// tops are touching. Whatever you told us about that setting, it is on.'
  ///
  /// Sent to both phones of a pair, because the interaction takes two: if it
  /// fired, neither of them had it turned off, whatever either of them said.
  ///
  /// This is inference, not detection — iOS offers no way to observe NameDrop,
  /// so what the host actually saw was two screens going away together on a
  /// pair the layout says is dangerous. It is enough to reopen a question and
  /// nowhere near enough to make an accusation, which is why the only thing it
  /// does is set the state back to waiting.
  static const nameDropSuspected = 'nameDropSuspected';

  static const pong = 'pong';
}

/// One entity's transform at a given tick.
///
/// Short keys and trimmed precision: this rides the wire 60 times a second for
/// every entity in the world.
class EntityState {
  const EntityState({
    required this.id,
    required this.x,
    required this.y,
    required this.angle,
    required this.vx,
    required this.vy,
  });

  final String id;
  final double x;
  final double y;
  final double angle;
  final double vx;
  final double vy;

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': _r(x),
    'y': _r(y),
    'a': _r(angle),
    'vx': _r(vx),
    'vy': _r(vy),
  };

  static EntityState fromJson(Map<String, dynamic> j) => EntityState(
    id: j['id'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    angle: (j['a'] as num).toDouble(),
    vx: (j['vx'] as num).toDouble(),
    vy: (j['vy'] as num).toDouble(),
  );

  /// Trim to 0.001 world units (= 10 micrometres at this scale). Well below
  /// what any screen can show, and it keeps snapshots small.
  static double _r(double v) => (v * 1000).roundToDouble() / 1000;
}
