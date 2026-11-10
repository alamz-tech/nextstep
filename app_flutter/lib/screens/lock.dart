import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';

/// Quick-exit disguise: a working calculator with no app branding.
/// To return: with a PIN, type it and press "="; without a PIN, press and hold "=".
class NeutralScreen extends StatefulWidget {
  const NeutralScreen({super.key});
  @override
  State<NeutralScreen> createState() => _NeutralScreenState();
}

class _NeutralScreenState extends State<NeutralScreen> {
  String display = '0', entry = '';
  double? acc;
  String? op;

  void _press(String l) => setState(() {
        if (RegExp(r'[0-9.]').hasMatch(l)) {
          entry = (entry == '0' ? '' : entry) + l;
          display = entry;
        } else if (l == 'C') {
          display = '0';
          entry = '';
          acc = null;
          op = null;
        } else {
          if (l == '=' && context.read<AppState>().unlockWithPin(entry)) return;
          _eval();
          op = l == '=' ? null : l;
          entry = '';
        }
      });

  void _eval() {
    final v = double.tryParse(entry);
    if (v == null) return;
    acc = (acc == null || op == null)
        ? v
        : switch (op) { '+' => acc! + v, '−' => acc! - v, '×' => acc! * v, '÷' => v == 0 ? 0 : acc! / v, _ => v };
    final a = acc!;
    display = a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    Widget key(String l) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: SizedBox(
              height: 64,
              child: FilledButton.tonal(
                key: Key('calc-$l'),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () => _press(l),
                onLongPress: l == '=' ? s.unlockNoPin : null,
                child: Text(l, style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        );
    return Theme(
      data: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFA3305A)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Calculator')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.bottomRight,
                    padding: const EdgeInsets.all(20),
                    child: Text(display, maxLines: 1, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300)),
                  ),
                ),
                for (final row in [['7', '8', '9', '÷'], ['4', '5', '6', '×'], ['1', '2', '3', '−'], ['C', '0', '.', '+'], ['=']])
                  Row(children: [for (final l in row) key(l)]),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
