import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import 'pin_pad.dart';

/// PIN unlock screen (shown on resume when a PIN is set). Neutral wording.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? err;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline, size: 40, color: NsColors.of(context).primary),
              const SizedBox(height: 12),
              Text(s.t('app', 'unlock_title'), style: Theme.of(context).textTheme.headlineSmall),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: NsColors.of(context).accent))),
              const SizedBox(height: 12),
              PinPad(onComplete: (p) {
                if (!s.unlock(p)) setState(() => err = s.t('app', 'pin_wrong'));
              }),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Quick-exit disguise: a working calculator with no app branding.
/// To return: type your PIN and press "="; without a PIN, press and hold "=".
class NeutralScreen extends StatefulWidget {
  const NeutralScreen({super.key});
  @override
  State<NeutralScreen> createState() => _NeutralScreenState();
}

class _NeutralScreenState extends State<NeutralScreen> {
  String display = '0';
  String entry = '';
  double? acc;
  String? op;

  void _digit(String d) => setState(() {
        entry = (entry == '0' ? '' : entry) + d;
        display = entry;
      });

  void _op(String o) => setState(() {
        _eval();
        op = o;
        entry = '';
      });

  void _eval() {
    final v = double.tryParse(entry);
    if (v == null) return;
    if (acc == null || op == null) {
      acc = v;
    } else {
      acc = switch (op) { '+' => acc! + v, '−' => acc! - v, '×' => acc! * v, '÷' => v == 0 ? 0 : acc! / v, _ => v };
    }
    display = acc!.toStringAsFixed(acc! % 1 == 0 ? 0 : 4).replaceFirst(RegExp(r'\.?0+$'), '');
    if (display.isEmpty) display = '0';
  }

  void _equals(AppState s) {
    if (s.hasPin && s.unlock(entry)) return;
    setState(() {
      _eval();
      op = null;
      entry = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    Widget btn(String l, VoidCallback f, {VoidCallback? long, Color? bg}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: SizedBox(
              height: 64,
              child: FilledButton.tonal(
                key: Key('calc-$l'),
                style: FilledButton.styleFrom(backgroundColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: f,
                onLongPress: long,
                child: Text(l, style: const TextStyle(fontSize: 24)),
              ),
            ),
          ),
        );
    return Theme(
      data: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blueGrey),
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
                    child: Text(display, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w300), maxLines: 1),
                  ),
                ),
                for (final row in [['7', '8', '9', '÷'], ['4', '5', '6', '×'], ['1', '2', '3', '−'], ['C', '0', '.', '+']])
                  Row(children: [
                    for (final l in row)
                      btn(l, () {
                        if (RegExp(r'[0-9.]').hasMatch(l)) {
                          _digit(l);
                        } else if (l == 'C') {
                          setState(() {
                            display = '0';
                            entry = '';
                            acc = null;
                            op = null;
                          });
                        } else {
                          _op(l);
                        }
                      }),
                  ]),
                Row(children: [
                  btn('=', () => _equals(s), long: s.hasPin ? null : () => s.unlock(null), bg: Colors.blueGrey.shade200),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
