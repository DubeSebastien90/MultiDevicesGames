import 'package:flutter/material.dart';

import '../model/name_drop_status.dart';
import '../platform/name_drop_support.dart';
import 'lobby_flow_style.dart';

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

String _localised(Map<String, dynamic> table, BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return (table[code] ?? table['en']!) as String;
}

class _NameDropNotice extends StatelessWidget {
  const _NameDropNotice();

  @override
  Widget build(BuildContext context) {
    final setting = _localised(_settingName, context);

    return Dialog.fullscreen(
      backgroundColor: LobbyFlowColors.paper,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: LobbyMark(
                      icon: Icons.contact_page_outlined,
                      // Yellow, not coral: nothing has gone wrong yet. This is
                      // the same "here is what is about to happen" the table
                      // change screen wears.
                      color: LobbyFlowColors.yellow,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const LobbyTitle('One thing before you play'),
                  const SizedBox(height: 14),
                  Text(
                    'This game puts phones edge to edge. When the tops of two '
                    'iPhones touch, iOS pops up a card offering to share your '
                    'contact details — over the game, mid-round.',
                    style: LobbyText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Turning off “$setting” stops it.',
                    style: LobbyText.label,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Three answers, three weights. Green is the one that fixes
                  // it, the field grey pair below are the ways of not fixing it
                  // yet — and none of them is a flat Material button any more.
                  LobbyPillButton(
                    onPressed: () =>
                        Navigator.of(context).pop(NameDropStatus.turnedOff),
                    label: 'Already done',
                    background: LobbyFlowColors.green,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 17,
                    radius: LobbyMetrics.bigRadius,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  const SizedBox(height: 10),
                  LobbyPillButton(
                    onPressed: () => _showHow(context),
                    label: 'How?',
                    background: LobbyFlowColors.purple,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 17,
                    radius: LobbyMetrics.bigRadius,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  const SizedBox(height: 10),
                  LobbyPillButton(
                    onPressed: () =>
                        Navigator.of(context).pop(NameDropStatus.declined),
                    label: 'No thanks',
                    background: LobbyFlowColors.field,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 17,
                    radius: LobbyMetrics.bigRadius,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Either way, this is the last you’ll hear of it.',
                    style: LobbyText.body,
                    textAlign: TextAlign.center,
                  ),
                ],
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
    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The back pill pops with nothing, which is what tells the
                // notice underneath that these instructions were not followed
                // through — the same meaning the app bar's arrow carried.
                LobbyHeader(
                  title: 'Turning it off',
                  onBack: () => Navigator.of(context).pop(),
                ),
                // Centred rather than a plain list: with the words gone the
                // four shots no longer fill the screen, and hanging them from
                // the header leaves the gap above the answer instead of
                // around them. Still scrolls if a small phone needs it to.
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Two by two, so all four fit above the answer
                          // without scrolling: a walkthrough you have to
                          // scroll is one you lose your place in halfway
                          // through.
                          GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            children: [
                              for (final (i, shot) in _shots.indexed)
                                _Step(
                                  number: i + 1,
                                  shot: shot,
                                  cropAlignment: _cropAlignment[i],
                                ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Everything else about AirDrop keeps working.',
                            style: LobbyText.body,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Outside the list on purpose: it is the answer to the whole
                // screen, and on a short phone the four steps push anything
                // below them off the bottom — where an answer nobody scrolls
                // to is an answer nobody gives.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: LobbyPillButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: Icons.check,
                    label: 'Done',
                    background: LobbyFlowColors.green,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 17,
                    iconSize: 20,
                    radius: LobbyMetrics.bigRadius,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tap: a picture of the row to touch, numbered.
///
/// A tile each rather than one list, so the four of them read as four things
/// to do in turn — a checklist you can look up at between taps and find your
/// place in — instead of a paragraph with numbers down the side.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.shot,
    required this.cropAlignment,
  });

  final int number;
  final String shot;
  final double cropAlignment;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LobbyMetrics.bigRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/sdk/screenshots/$shot.png',
            fit: BoxFit.cover,
            alignment: Alignment(0, cropAlignment),
          ),
          // Top *right*: step one's red circle is in the opposite corner, and
          // a badge there would land on the one thing the shot is of.
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LobbyFlowColors.cyan,
                shape: BoxShape.circle,
                // A ring, because the badge sits on screenshots that are
                // light in three corners out of four and near-black in the
                // fourth.
                border: Border.all(color: LobbyFlowColors.paper, width: 2),
              ),
              child: Text(
                '$number',
                style: LobbyText.count.copyWith(fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
