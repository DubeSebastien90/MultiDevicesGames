import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/game_audio.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
import 'package:multiscreen_slingshot/sdk/audio/ui_audio.dart';
import 'package:multiscreen_slingshot/sdk/ui/lobby_flow_style.dart';

void main() {
  late _HeardAudio audio;

  setUp(() => UiAudio.speaker = audio = _HeardAudio());
  tearDown(() => UiAudio.speaker = const SilentLocalAudio());

  Future<void> mount(WidgetTester tester, VoidCallback? onPressed) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: LobbyPillButton(label: 'Go', onPressed: onPressed),
          ),
        ),
      ));

  testWidgets('a menu button boups, then does its job', (tester) async {
    var pressed = 0;
    await mount(tester, () => pressed++);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(pressed, 1);
    expect(audio.played, hasLength(1));
    expect(Sounds.buttonPress, contains(audio.played.single));
  });

  testWidgets('a disabled button stays silent', (tester) async {
    await mount(tester, null);

    await tester.tap(find.text('Go'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(audio.played, isEmpty);
  });
}

class _HeardAudio implements LocalAudio {
  final played = <SoundCue>[];

  @override
  SoundHandle play(SoundCue cue, {bool loop = false, double volume = 1.0}) {
    played.add(cue);
    return SoundHandle.none;
  }

  @override
  void stopSound(SoundHandle handle, {Duration fade = Duration.zero}) {}
}
