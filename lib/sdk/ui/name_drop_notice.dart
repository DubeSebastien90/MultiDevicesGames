import 'package:flutter/material.dart';

import '../model/name_drop_status.dart';
import '../platform/name_drop_support.dart';
import 'sticker/sticker.dart';

/// Shows [showNameDropNotice] over [child] the first time this is built with
/// an unanswered question on a phone that can actually NameDrop.
///
/// Wrapped around the lobby rather than built into it, for two reasons. The
/// lobby has no state of its own and does not want any; and *the lobby* is the
/// deliberate choice of moment. It is the last screen before phones start
/// moving toward each other, and the only one where a full-screen interruption
/// costs nothing — putting this on the placement or game screens would mean
/// interrupting a round to complain about interruptions.
///
/// Which is also why a reset arriving mid-game does not reopen this. The state
/// flips silently and the question comes back the next time somebody walks
/// through here.
class NameDropGate extends StatefulWidget {
  const NameDropGate({super.key, required this.child});

  final Widget child;

  @override
  State<NameDropGate> createState() => _NameDropGateState();
}

class _NameDropGateState extends State<NameDropGate> {
  @override
  void initState() {
    super.initState();
    // After the first frame: this runs on the way into the lobby, and showing
    // a dialog from inside a build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    final supported = await NameDropSupport.onThisDevice();
    debugPrint('[namedrop] onThisDevice=$supported');
    if (!supported) return;

    final status = await NameDropPref.load();
    debugPrint('[namedrop] stored status=$status');
    if (status != NameDropStatus.waiting) return;

    if (!mounted) {
      debugPrint('[namedrop] gate unmounted before dialog could show');
      return;
    }

    debugPrint('[namedrop] showing notice');
    final answer = await showNameDropNotice(context);
    debugPrint('[namedrop] answer=$answer');
    // A no-answer stays unwritten, so the question survives to the next lobby.
    if (answer != NameDropStatus.waiting) await NameDropPref.save(answer);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks an iPhone owner to turn off Bringing Devices Together before the game
/// starts.
///
/// That setting is what makes NameDrop fire when the tops of two iPhones meet,
/// and this platform spends its whole life asking people to put the tops of
/// phones together. [NameDropOptimizer] turns phones around to keep the
/// dangerous ends apart and gets most tables, but it cannot get all of them,
/// and a Share Contact card over a running game is the one interruption nobody
/// can dismiss quickly.
///
/// **Everything here is words.** There is no button that opens the right page
/// of Settings, because no such button can exist: `UIApplication`'s public
/// entry point opens only this app's own pane, and the `App-Prefs:` scheme that
/// reaches General → AirDrop is one Apple rejects apps for using. So the second
/// button shows the path and trusts people to walk it — which is also why
/// nothing here can verify the answer, and why the host quietly disbelieves it
/// when two phones get interrupted together.
///
/// Returns the state the answer implies. Never null: the sheet cannot be
/// dismissed except by choosing, and the instructions open *over* it, so
/// backing out of them lands back on the question rather than escaping it.
Future<NameDropStatus> showNameDropNotice(BuildContext context) async {
  final answer = await showDialog<NameDropStatus>(
    context: context,
    barrierDismissible: false,
    // Edge to edge: the notice keeps its own content inside the safe area, and
    // the default inset would leave the scrim showing behind the notch.
    useSafeArea: false,
    builder: (_) => const _NameDropNotice(),
  );
  // Only reachable if something outside this file pops the route — a state
  // restoration, a test pumping a different widget. Asking again next time is
  // the safe reading of "no answer".
  return answer ?? NameDropStatus.waiting;
}

/// The setting's name as the Settings app spells it, per language.
///
/// Somebody hunting for 'Bringing Devices Together' on a French phone will not
/// find it — iOS shows these in the device's language, and the whole value of
/// this screen is that the words on it match the words on the next one.
/// Anything not listed falls back to English, which is what the device shows
/// for unlisted languages anyway.
const _settingName = {
  'en': 'Bringing Devices Together',
  'fr': 'Rapprochement des appareils',
  'es': 'Acercar dispositivos',
  'de': 'Geräte zusammenführen',
};

/// The three rows to tap, as the Settings app spells them, per language.
///
/// Back after a spell of pictures alone. A screenshot shows *where* to tap and
/// says nothing you can search for: somebody who has drifted a screen away, or
/// whose iOS lays things out a little differently, needs the word to look for.
/// The pictures and the words answer different halves of the same question.
const _pathNames = {
  'en': ['Settings', 'General', 'AirDrop'],
  'fr': ['Réglages', 'Général', 'AirDrop'],
  'es': ['Ajustes', 'General', 'AirDrop'],
  'de': ['Einstellungen', 'Allgemein', 'AirDrop'],
};

String _localised(Map<String, dynamic> table, BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return (table[code] ?? table['en']!) as String;
}

List<String> _path(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return (_pathNames[code] ?? _pathNames['en']!).cast<String>();
}

class _NameDropNotice extends StatelessWidget {
  const _NameDropNotice();

  @override
  Widget build(BuildContext context) {
    final setting = _localised(_settingName, context);

    return Dialog.fullscreen(
      backgroundColor: St.bg,
      child: StickerBackground(
        shapes: lobbyShapes,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Blue, not red: nothing has gone wrong yet. This is the
                    // same "here is what is about to happen" the table change
                    // screen wears.
                    const Center(
                      child: StickerMark(
                        icon: Symbols.contact_page_rounded,
                        color: St.blue,
                        size: 72,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'One thing before you play',
                      textAlign: TextAlign.center,
                      style: St.display(30, height: 1.05),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This game puts phones edge to edge. When the tops of two '
                      'iPhones touch, iOS pops up a card offering to share your '
                      'contact details — over the game, mid-round.',
                      style: St.body(
                        16,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Turning off “$setting” stops it.',
                      style: St.body(17, weight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    // Three answers, three weights. Green is the one that fixes
                    // it; the two below are the ways of not fixing it yet.
                    StickerWideButton(
                      onTap: () =>
                          Navigator.of(context).pop(NameDropStatus.turnedOff),
                      label: 'Already done',
                      height: 54,
                      fontSize: 20,
                      icon: Symbols.check_rounded,
                      color: St.go,
                      textColor: St.white,
                    ),
                    const SizedBox(height: 12),
                    StickerWideButton(
                      onTap: () => _showHow(context),
                      label: 'How?',
                      height: 54,
                      fontSize: 20,
                      icon: Symbols.help_rounded,
                      color: St.premium,
                      textColor: St.white,
                    ),
                    const SizedBox(height: 12),
                    StickerWideButton(
                      onTap: () =>
                          Navigator.of(context).pop(NameDropStatus.declined),
                      label: 'No thanks',
                      height: 54,
                      fontSize: 20,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Either way, this is the last you’ll hear of it.',
                      style: St.body(
                        14,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the walkthrough over the notice, and closes the notice as done only
  /// if they came back off the end of it.
  ///
  /// Backing out means they did not follow it through, and the honest record of
  /// that is the question they were already being asked — still underneath,
  /// still unanswered.
  Future<void> _showHow(BuildContext context) async {
    // An ordinary push, not a fullscreen dialog: this is somewhere you go and
    // come back from, and the back arrow says so. A dialog's close button
    // reads as "cancel", which is the wrong word for reaching the end of a
    // set of instructions.
    final done = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const _HowScreen()));
    if (done == true && context.mounted) {
      Navigator.of(context).pop(NameDropStatus.turnedOff);
    }
  }
}

/// Where each screenshot's red circle sits, as a vertical alignment for the
/// square crop.
///
/// The four shots are different shapes and mostly dead space, so they are
/// cropped to a common square rather than shown whole. This is the knob that
/// says which square: -1 keeps the top, 1 the bottom. Re-tune it if the shots
/// are ever retaken.
const _cropAlignment = [-1.0, 0.75, 1.0, 0.45];

/// The walkthrough: four taps, shown.
///
/// Words were all there was, and that is a platform fact rather than a gap
/// waiting to be filled — `UIApplication` opens only this app's own pane, and
/// the `App-Prefs:` scheme that would land on General → AirDrop is one Apple
/// rejects apps for using. So the screen's whole job is to make the path
/// unmistakable, and a picture of the row to tap, circled, does that better
/// than any sentence naming it. The numbers are the only text left.
class _HowScreen extends StatelessWidget {
  const _HowScreen();

  static const _shots = [
    'step_1_settings',
    'step_2_general',
    'step_3_airdrop',
    'step_4_toggle',
  ];

  @override
  Widget build(BuildContext context) {
    final path = _path(context);
    final setting = _localised(_settingName, context);

    // Verb and target kept apart, because they are read differently: the verb
    // is an instruction you already understand, and the target is the word you
    // are about to go hunting for on the screen in the picture below it.
    final steps = <(String, String)>[
      ('Open', path[0]),
      ('Tap', path[1]),
      ('Tap', path[2]),
      ('Turn off', '“$setting”'),
    ];

    return StickerPage(
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The back button pops with nothing, which is what tells the notice
          // underneath that these instructions were not followed through.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: StickerHeader(
              'Turning it off',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          // Centred rather than hung from the header: the four cards do not
          // fill a tall phone, and leaving the slack under them puts it between
          // the walkthrough and its answer. Still scrolls where a short phone
          // needs it to.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Two by two, so all four are in view at once: a
                    // walkthrough you have to scroll is one you lose your place
                    // in halfway through.
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      clipBehavior: Clip.none,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                      children: [
                        for (final (i, shot) in _shots.indexed)
                          _Step(
                            number: i + 1,
                            verb: steps[i].$1,
                            target: steps[i].$2,
                            shot: shot,
                            cropAlignment: _cropAlignment[i],
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Everything else about AirDrop keeps working.',
                      style: St.body(
                        14,
                        weight: FontWeight.w500,
                        color: St.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Outside the scroll on purpose: it is the answer to the whole
          // screen, and on a short phone the four steps push anything below
          // them off the bottom — where an answer nobody scrolls to is an
          // answer nobody gives.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: StickerWideButton(
              onTap: () => Navigator.of(context).pop(true),
              icon: Symbols.check_rounded,
              label: 'Done',
              color: St.go,
              textColor: St.white,
              height: 66,
              fontSize: 26,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tap, as a card: its number, what to do, and a picture of where.
///
/// The number and the words sit *above* the shot rather than on it. A badge
/// dropped into a corner of a screenshot has to dodge whatever that screenshot
/// is of — which is why it used to be pinned top-right, away from step one's
/// circle — and a caption laid over one is unreadable on a light iOS screen as
/// often as not. Given their own strip they are always in the same place, and
/// the picture below is left to be a picture.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.verb,
    required this.target,
    required this.shot,
    required this.cropAlignment,
  });

  final int number;
  final String verb;
  final String target;
  final String shot;
  final double cropAlignment;

  /// Squarer than the other stickers: a screenshot is a rectangle, and
  /// rounding it hard starts cutting off the thing it is a picture of.
  static const _cardRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: _cardRadius,
      shadow: 4,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: St.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: St.ink, width: 2),
                  ),
                  child: Text(
                    '$number',
                    style: St.display(13, color: St.white, height: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$verb ',
                          style: St.body(
                            12,
                            weight: FontWeight.w500,
                            color: St.muted,
                          ),
                        ),
                        TextSpan(
                          text: target,
                          style: St.body(12, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Whatever the caption leaves. Four captions of different lengths
          // means four pictures of slightly different heights, which is the
          // price of every card being as tall as the tallest — and cheaper
          // than a caption cut off mid-word.
          Expanded(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: St.ink, width: 2)),
              ),
              child: Image.asset(
                'assets/sdk/screenshots/$shot.png',
                fit: BoxFit.cover,
                alignment: Alignment(0, cropAlignment),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
