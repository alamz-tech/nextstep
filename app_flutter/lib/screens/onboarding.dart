import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'pin_pad.dart';

/// Consent → age tier (under 15 exits kindly) → language → optional PIN.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0; // 0 consent, 1 data info, 2 age, 3 language, 4 pin, 9 under-15 exit, 8 not now
  String? tier;
  String? firstPin;
  String? pinError;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;

    Widget langToggle() => SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'en', label: Text(s.t('menu', 'btn_en'))),
            ButtonSegment(value: 'pcm', label: Text(s.t('menu', 'btn_pcm'))),
          ],
          selected: {s.lang},
          showSelectedIcon: false,
          onSelectionChanged: (v) => s.setLang(v.first),
        );

    List<Widget> content;
    switch (step) {
      case 0:
        content = [
          Row(children: [const Logo(size: 48), const Spacer(), langToggle()]),
          const SizedBox(height: 20),
          Text(s.t('consent', 'intro'), style: tt.headlineSmall),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.t('consent', 'body'), style: tt.bodyLarge))),
          const SizedBox(height: 20),
          FilledButton(key: const Key('consent-agree'), onPressed: () => setState(() => step = 2), child: Text(s.t('consent', 'btn_agree'))),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => setState(() => step = 1), child: Text(s.t('consent', 'btn_data'))),
          const SizedBox(height: 10),
          TextButton(onPressed: () => setState(() => step = 8), child: Text(s.t('consent', 'btn_not_now'))),
        ];
      case 1:
        content = [
          Text(s.t('consent', 'btn_data'), style: tt.headlineSmall),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.t('consent', 'data'), style: tt.bodyLarge))),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => setState(() => step = 2), child: Text(s.t('consent', 'btn_agree'))),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => setState(() => step = 8), child: Text(s.t('consent', 'btn_not_now'))),
        ];
      case 8:
        content = [
          const Logo(size: 48),
          const SizedBox(height: 20),
          Text(s.t('consent', 'not_now'), style: tt.titleLarge),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: () => setState(() => step = 0), child: Text(s.t('sim', 'say_hi'))),
        ];
      case 2:
        content = [
          Text(s.t('consent', 'agreed'), style: tt.titleMedium?.copyWith(color: c.primary)),
          const SizedBox(height: 8),
          Text(s.t('age', 'ask'), style: tt.headlineSmall),
          const SizedBox(height: 20),
          for (final (key, label) in [('15_17', 'btn_15_17'), ('18_24', 'btn_18_24'), ('under_15', 'btn_under15')]) ...[
            OutlinedButton(
              key: Key('age-$key'),
              onPressed: () {
                if (key == 'under_15') {
                  s.completeOnboarding('under_15', s.lang);
                  setState(() => step = 9);
                } else {
                  setState(() {
                    tier = key;
                    step = 3;
                  });
                }
              },
              child: Text(s.t('age', label)),
            ),
            const SizedBox(height: 10),
          ],
        ];
      case 9:
        content = [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.support, width: 2)),
            child: Padding(padding: const EdgeInsets.all(18), child: Text(s.t('age', 'under15'), style: tt.bodyLarge)),
          ),
          const SizedBox(height: 16),
          Text('Nothing about you has been saved.', style: tt.bodySmall),
        ];
      case 3:
        content = [
          Text(s.t('app', 'lang_title'), style: tt.headlineSmall),
          const SizedBox(height: 20),
          for (final (l, label) in [('en', 'English'), ('pcm', 'Pidgin')]) ...[
            OutlinedButton(
              key: Key('lang-$l'),
              style: s.lang == l ? OutlinedButton.styleFrom(backgroundColor: c.primaryTint) : null,
              onPressed: () async {
                await s.setLang(l);
                setState(() => step = 4);
              },
              child: Text(label),
            ),
            const SizedBox(height: 10),
          ],
          Text('Hausa: coming later', style: tt.bodySmall),
        ];
      default:
        content = [
          Text(firstPin == null ? s.t('app', 'pin_title') : s.t('app', 'pin_again'), style: tt.headlineSmall),
          const SizedBox(height: 8),
          Text(s.t('app', 'pin_body'), style: tt.bodyMedium),
          const SizedBox(height: 16),
          if (pinError != null) Text(pinError!, style: TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
          PinPad(
            key: ValueKey(firstPin),
            onComplete: (pin) async {
              if (firstPin == null) {
                setState(() {
                  firstPin = pin;
                  pinError = null;
                });
              } else if (pin == firstPin) {
                await s.setPin(pin);
                await _finish(s);
              } else {
                setState(() {
                  firstPin = null;
                  pinError = s.t('app', 'pin_mismatch');
                });
              }
            },
          ),
          const SizedBox(height: 8),
          TextButton(key: const Key('pin-skip'), onPressed: busy ? null : () => _finish(s), child: Text(s.t('app', 'pin_skip'))),
        ];
    }
    return Scaffold(
      body: SafeArea(
        child: NsPage(maxWidth: 520, padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: content),
      ),
    );
  }

  Future<void> _finish(AppState s) async {
    setState(() => busy = true);
    await s.completeOnboarding(tier ?? '18_24', s.lang);
  }
}
