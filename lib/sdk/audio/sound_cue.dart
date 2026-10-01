library;

class SoundCue {
  const SoundCue(this.id, [this.asset]);

  const SoundCue.asset(String path) : id = path, asset = path;

  final String id;

  final String? asset;

  bool get exists => asset != null;

  @override
  String toString() => 'SoundCue($id)';
}

class SoundHandle {
  const SoundHandle(this.id);

  final int id;

  static const none = SoundHandle(-1);

  @override
  bool operator ==(Object other) => other is SoundHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SoundHandle($id)';
}
