import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/age_band.dart';
import 'sticker/sticker.dart';

class AgeGate extends StatefulWidget {
  const AgeGate({super.key, required this.builder});

  final Widget Function(BuildContext context, AgeBand band) builder;

  @override
  State<AgeGate> createState() => _AgeGateState();
}

class _AgeGateState extends State<AgeGate> {
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

    if (band == null) return const Scaffold(backgroundColor: St.bg);
    if (band == AgeBand.unknown) {
      return _AgeQuestionScreen(
        onAnswered: (answer) => setState(() => _band = answer),
      );
    }
    return widget.builder(context, band);
  }
}

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
                    'That date does not look right. Have another look.',
                    style: St.body(15, color: St.back),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
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
