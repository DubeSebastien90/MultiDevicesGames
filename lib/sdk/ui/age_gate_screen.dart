import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/age_band.dart';
import 'sticker/sticker.dart';

/// Holds the app back until [AgeGatePref] has an answer, then hands the answer
/// down.
///
/// A gate rather than a dialog over the top — the distinction matters. The
/// NameDrop notice can be a dialog because dismissing it costs nothing: the
/// question comes back next lobby. This one decides whether a text field that
/// broadcasts on the LAN exists at all, so there must be no frame in which the
/// app is on screen and the answer is not yet known. Passing [AgeBand] down as
/// a required argument rather than letting screens look it up themselves is the
/// same idea in the type system: a screen cannot forget to check something it
/// cannot be built without.
class AgeGate extends StatefulWidget {
  const AgeGate({super.key, required this.builder});

  final Widget Function(BuildContext context, AgeBand band) builder;

  @override
  State<AgeGate> createState() => _AgeGateState();
}

class _AgeGateState extends State<AgeGate> {
  /// Null while the read is in flight, which is a different thing from
  /// [AgeBand.unknown] — one means "ask nothing yet", the other means "ask".
  AgeBand? _band;

  @override
  void initState() {
    super.initState();
    AgeGatePref.load().then((band) {
      if (mounted) setState(() => _band = band);
    });
  }

  @override
  Widget build(BuildContext context) {
    final band = _band;
    // A bare Scaffold, not a spinner. This is one disk read on a launch that is
    // already loading sprites; a spinner that flashes for 40ms reads as a
    // fault. Yellow rather than the theme's dark default: this is the first
    // frame of the app, and it should be the colour the app actually is.
    if (band == null) return const Scaffold(backgroundColor: St.bg);
    if (band == AgeBand.unknown) {
      return _AgeQuestionScreen(
        onAnswered: (answer) => setState(() => _band = answer),
      );
    }
    return widget.builder(context, band);
  }
}

/// Asks when somebody was born, and gives away nothing about why.
///
/// The whole design of this screen is in what it does **not** do:
///
/// * It does not ask "are you over 13?". A yes/no question with an obvious
///   right answer collects the obvious right answer, from everyone, and the
///   number in the question is the instruction manual for beating it.
/// * The fields start **empty**. A year wheel parked on 2010 has proposed an
///   answer, and a surprising share of people will take a proposal.
/// * Nothing on the way out changes by answer. No apology, no explanation, no
///   confirmation — both answers land on the same next screen. A child who is
///   never told a boundary was crossed has no reason to go back and try again,
///   and no way to know which field to lie in.
/// * The only complaint it can make is about a date that is impossible for
///   reasons of arithmetic. A validator that objects to young answers is the
///   threshold, read aloud.
class _AgeQuestionScreen extends StatefulWidget {
  const _AgeQuestionScreen({required this.onAnswered});

  final ValueChanged<AgeBand> onAnswered;

  @override
  State<_AgeQuestionScreen> createState() => _AgeQuestionScreenState();
}

class _AgeQuestionScreenState extends State<_AgeQuestionScreen> {
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  int? _month;
  final _yearController = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  int? get _year => int.tryParse(_yearController.text.trim());

  bool get _complete => _month != null && (_year ?? 0) >= 1000;

  void _submit() {
    final month = _month;
    final year = _year;
    if (month == null || year == null) return;

    final now = DateTime.now();
    if (!AgeGatePref.isPlausible(
      birthYear: year,
      birthMonth: month,
      now: now,
    )) {
      setState(() => _showError = true);
      return;
    }

    // The date exists for exactly as long as this method runs. What survives is
    // one of two words.
    final band = AgeGatePref.classify(
      birthYear: year,
      birthMonth: month,
      now: now,
    );
    AgeGatePref.save(band);
    widget.onAnswered(band);
  }

  @override
  Widget build(BuildContext context) {
    final fieldStyle = St.body(20, weight: FontWeight.w700);
    final hintStyle = fieldStyle.copyWith(
      color: St.muted.withValues(alpha: .6),
    );

    // No back, no swipe, no skip. There is no path through this screen that
    // does not go past the question.
    return PopScope(
      canPop: false,
      child: StickerPage(
        maxWidth: 460,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: -2 * math.pi / 180,
                  child: Text(
                    'Before you play',
                    textAlign: TextAlign.center,
                    style: St.display(40, height: 1),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'When were you born?',
                  style: St.body(18, color: St.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),

                // Still a [DropdownButtonFormField], on a sticker: a month is a
                // closed list of twelve, and a field you type into would invite
                // typing one of them wrong.
                StickerCard(
                  radius: 18,
                  shadow: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: DropdownButtonFormField<int>(
                    initialValue: _month,
                    isExpanded: true,
                    decoration: const InputDecoration(border: InputBorder.none),
                    hint: Text('Month', style: hintStyle),
                    style: fieldStyle,
                    dropdownColor: St.white,
                    borderRadius: BorderRadius.circular(18),
                    icon: const StIcon(Symbols.expand_more_rounded, size: 28),
                    items: [
                      for (var i = 0; i < _months.length; i++)
                        DropdownMenuItem(
                          value: i + 1,
                          child: Text(_months[i], style: fieldStyle),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _month = value;
                      _showError = false;
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                StickerField(
                  controller: _yearController,
                  hintText: 'YYYY',
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onChanged: (_) => setState(() => _showError = false),
                  onSubmitted: (_) {
                    if (_complete) _submit();
                  },
                ),
                if (_showError) ...[
                  const SizedBox(height: 14),
                  Text(
                    // Says the date is impossible, not that the person is.
                    'That date does not look right. Have another look.',
                    style: St.body(15, color: St.back),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                // Disabled rather than defaulted. The waiting button is what
                // keeps the fields empty, and empty fields are what keep the
                // screen from suggesting an answer. Half strength says so
                // without a word: every unavailable button is drawn this way.
                StickerWideButton(
                  label: 'Continue',
                  icon: Symbols.arrow_forward_rounded,
                  color: St.go,
                  textColor: St.white,
                  height: 66,
                  fontSize: 26,
                  onTap: _complete ? _submit : null,
                ),
                const SizedBox(height: 18),
                Text(
                  'This stays on your phone, and the date itself is not '
                  'kept. Nobody else on the network sees it.',
                  style: St.body(14, weight: FontWeight.w500, color: St.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
