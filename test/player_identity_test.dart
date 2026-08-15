import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/audio/sound_cue.dart';
import 'package:multiscreen_slingshot/sdk/audio/sounds.dart';
import 'package:multiscreen_slingshot/sdk/model/player.dart';
import 'package:multiscreen_slingshot/sdk/model/player_character.dart';
import 'package:multiscreen_slingshot/sdk/model/player_color.dart';
import 'package:multiscreen_slingshot/sdk/render/player_art.dart';

/// The colour is the character, and everything a game can ask about a player
/// hangs off that one join. What is worth testing is the join itself: that no
/// palette entry can exist without a character, and that art and sound answer
/// for every one of them without an asset in the project.
void main() {
  group('the character table', () {
    test('every colour has one, and no two share it', () {
      expect(Cast.all, hasLength(PlayerPalette.size));

      final ids = <String>{};
      for (final color in PlayerPalette.all) {
        final character = Cast.byColorId(color.id);
        expect(
          character,
          isNotNull,
          reason: '${color.id} has no character — the two tables have drifted',
        );
        expect(ids.add(character!.colorId), isTrue, reason: 'duplicate entry');
        expect(character.name, isNotEmpty);
      }
    });

    test('a colour from a newer build resolves rather than crashing', () {
      // An id read off the wire that this build has never heard of. It cannot
      // normally happen — the join handshake compares catalog fingerprints —
      // but a lookup that throws would take a round down with it.
      const unknown = PlayerColor(
        id: 'chartreuse',
        name: 'Chartreuse',
        value: Color(0xFF7FFF00),
        onColor: Color(0xFF203000),
      );
      expect(Cast.byColorId(unknown.id), isNull);
      expect(Cast.of(unknown), isNotNull);
    });
  });

  group('art', () {
    test('is cached per colour and slot', () {
      // A game may ask for this inside a render loop, so two asks must not be
      // two objects.
      final a = PlayerArt.of(PlayerPalette.green, PlayerArtSlot.topdown);
      final b = PlayerArt.of(PlayerPalette.green, PlayerArtSlot.topdown);
      expect(identical(a, b), isTrue);

      final face = PlayerArt.of(PlayerPalette.green, PlayerArtSlot.face);
      expect(identical(a, face), isFalse);
    });

    test('paints before the file has arrived', () {
      // The rule the whole design rests on: art never decides whether a round
      // starts. Nothing has been loaded at this point and every player still
      // has a picture, so a game never writes a fallback.
      for (final color in PlayerPalette.all) {
        for (final slot in PlayerArtSlot.values) {
          final art = PlayerArt.of(color, slot);
          expect(art.isLoaded, isFalse);

          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          art.draw(canvas, const Offset(10, 10), worldSize: 3, angle: 0.4);
          expect(recorder.endRecording().approximateBytesUsed, greaterThan(0));
        }
      }
    });

    testWidgets('every character has a file, and every file decodes', (
      tester,
    ) async {
      // Sixteen images, declared in the pubspec and named in `Cast`. A typo in
      // either is a player who is a flat square forever, which is exactly the
      // kind of failure that is invisible until somebody is at the table.
      for (final color in PlayerPalette.all) {
        for (final slot in PlayerArtSlot.values) {
          final art = PlayerArt.of(color, slot);
          art.beginLoading();
          await tester.runAsync(() async {
            // The decode is off the platform thread; give it room to land.
            for (var i = 0; i < 50 && !art.isLoaded; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          });
          expect(
            art.isLoaded,
            isTrue,
            reason: '${color.id}/${slot.name} never decoded — check the path '
                'in Cast and the asset entry in pubspec.yaml',
          );
        }
      }
    });

    testWidgets('draws the picture once it has one', (tester) async {
      final art = PlayerArt.of(PlayerPalette.brown, PlayerArtSlot.topdown);
      art.beginLoading();
      await tester.runAsync(() async {
        for (var i = 0; i < 50 && !art.isLoaded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      art.draw(canvas, Offset.zero, worldSize: 3, opacity: 0.5);
      expect(recorder.endRecording().approximateBytesUsed, greaterThan(0));
    });

    testWidgets('the widget and the canvas are the same drawing', (
      tester,
    ) async {
      // Not a screenshot comparison — the guarantee is structural. The widget
      // is a CustomPaint over the same private paint routine, so a change to
      // the art cannot land in one surface and miss the other.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: PlayerArt.of(
              PlayerPalette.pink,
              PlayerArtSlot.face,
            ).widget(size: 64),
          ),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.getSize(find.byType(SizedBox).first), const Size(64, 64));
    });
  });

  group('a player', () {
    const green = Player(
      phoneId: 'p1',
      color: PlayerPalette.green,
      label: 'Pixel 7',
    );

    test('reads as a colour and a character', () {
      expect(green.character.name, 'Frog');
      expect(green.title, 'Green Frog');
      expect(green.label, 'Pixel 7');
    });

    test('carries its own voice', () {
      expect(green.soundSad.id, 'green.sad');
      expect(green.soundHappy.id, 'green.happy');
      // Recorded, unlike most of the library — so this one really plays.
      expect(green.soundHappy.exists, isTrue);
      expect(green.soundSad.asset, endsWith('green-sad.wav'));
    });

    test('is the same player across two assemblies of the roster', () {
      // The roster is rebuilt whenever a view is, so equality has to be by
      // identity-of-person rather than of object.
      const again = Player(phoneId: 'p1', color: PlayerPalette.green);
      expect(again, green);
    });
  });

  group('the roster', () {
    final roster = Roster([
      const Player(phoneId: 'p1', color: PlayerPalette.green),
      const Player(phoneId: 'p2', color: PlayerPalette.orange),
      const Player(phoneId: 'p3', color: PlayerPalette.blue),
    ]);

    test('finds a player by phone and by colour', () {
      expect(roster.byPhone('p2')?.color.id, 'orange');
      expect(roster.byColor(PlayerPalette.blue)?.phoneId, 'p3');
      expect(roster.byPhone('p9'), isNull);
      expect(roster.byColor(PlayerPalette.red), isNull);
    });

    test('names everyone else', () {
      expect(
        roster.others('p1').map((p) => p.phoneId),
        ['p2', 'p3'],
      );
    });
  });

  group('the sound library', () {
    test('is named in full, whether or not the recording exists', () {
      // The point of the table: a cue can be referenced by a game long before
      // anybody records it, and a cue with no asset is a silence rather than a
      // failure. Only `pop` has been recorded so far.
      for (final cue in Sounds.all) {
        expect(cue.id, isNotEmpty);
      }
      expect(Sounds.pop.exists, isTrue);
      expect(Sounds.countdown.exists, isFalse);
    });

    test('gives every colour a happy and a sad', () {
      for (final color in PlayerPalette.all) {
        expect(PlayerSounds.happy(color).id, '${color.id}.happy');
        expect(PlayerSounds.sad(color).id, '${color.id}.sad');
      }
    });

    testWidgets('every recorded cue resolves to a file that is really there', (
      tester,
    ) async {
      // The audio counterpart of the image test, and it catches the same class
      // of mistake: a path typo or a missing `pubspec.yaml` entry is a player
      // who is silent forever, which nobody notices until they are at a table.
      final cues = <SoundCue>[
        ...Sounds.all,
        for (final color in PlayerPalette.all) ...[
          PlayerSounds.happy(color),
          PlayerSounds.sad(color),
        ],
      ].where((c) => c.exists);

      expect(cues, hasLength(17), reason: 'a pop and sixteen player clips');

      for (final cue in cues) {
        await tester.runAsync(() async {
          final bytes = await rootBundle.load(cue.asset!);
          expect(
            bytes.lengthInBytes,
            greaterThan(0),
            reason: '${cue.id} is declared but empty',
          );
        });
      }
    });

    test('does not allocate a new cue per call', () {
      // A sim reaching for this inside a step must not make garbage.
      expect(
        identical(
          PlayerSounds.sad(PlayerPalette.red),
          PlayerSounds.sad(PlayerPalette.red),
        ),
        isTrue,
      );
    });
  });
}
