import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 4-digit PIN entry with large touch targets.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onComplete, this.length = 4});
  final void Function(String pin) onComplete;
  final int length;
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String pin = '';

  void _tap(String d) {
    if (pin.length >= widget.length) return;
    setState(() => pin += d);
    if (pin.length == widget.length) {
      final p = pin;
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => pin = '');
        widget.onComplete(p);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NsColors.of(context);
    Widget key(String d) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 60,
            child: OutlinedButton(
              key: Key('pin-$d'),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: () => d == '⌫' ? setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1)) : _tap(d),
              child: Text(d, style: const TextStyle(fontSize: 22)),
            ),
          ),
        );
    return Column(children: [
      Semantics(
        label: '${pin.length} of ${widget.length} digits entered',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.length, (i) => Container(
                margin: const EdgeInsets.all(8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? c.primary : c.line),
              )),
        ),
      ),
      const SizedBox(height: 8),
      for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final d in row) d.isEmpty ? const SizedBox(width: 84) : key(d),
        ]),
    ]);
  }
}
