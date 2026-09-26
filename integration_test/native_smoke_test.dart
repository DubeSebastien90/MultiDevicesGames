import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/soloud_output.dart';
import 'package:multiscreen_slingshot/sdk/ui/intro_animation.dart';

/// Runs on the real device, with the real native libraries.
///
/// `flutter test` cannot reach either of these: it runs on the Dart VM with no
/// plugins, so a crash inside Rive's or SoLoud's native code is invisible
/// to the whole unit suite. This is the only place that class of failure can
/// be caught.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Rive runtime comes up', (tester) async {
    await IntroAnimation.initRuntime();
    expect(IntroAnimation.available, isTrue);
  }, skip: !IntroAnimation.platformSupportsRive);

  testWidgets('the intro renders its file without taking the app down', (
    tester,
  ) async {
    await IntroAnimation.initRuntime();

    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroAnimation(
          duration: const Duration(milliseconds: 800),
          onDone: () => done = true,
        ),
      ),
    );

    // Let it load and draw real frames.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done, isTrue);
    // Skipped where Rive renders by taking the process down. Skipped rather
    // than deleted: the day `rive_native` fixes Windows, removing this word is
    // how you find out.
  }, skip: !IntroAnimation.platformSupportsRive);

  testWidgets('a player voice plays through the real output', (tester) async {
    final out = SoLoudOutput();
    await out.play(1, 'assets/sdk/players/green-happy.wav');
    await tester.pump(const Duration(milliseconds: 600));
    await out.stop(1);
    await out.dispose();
  });
}
