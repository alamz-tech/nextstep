import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Private check: one question per screen. Works offline using the scoring rules
/// in the cached content bundle. Answers are never stored or sent; only the
/// result band is counted when online. Result is a next step, never a diagnosis.
class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});
  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  int i = -1; // -1 intro, 0..n-1 questions, n result
  final Map<String, String> answers = {};
  Map<String, dynamic>? result;
  bool showQ5Support = false;

  static const _labelKey = {'y': 'btn_yes', 'n': 'btn_no', 'ns': 'btn_not_sure', 'rn': 'btn_rather_not'};

  List<Map<String, dynamic>> _questions(AppState s) {
    final cfg = s.bundle?['check'] as Map<String, dynamic>?;
    final qs = (cfg?['questions'] as List?)?.cast<Map<String, dynamic>>();
    return qs ??
        [
          for (final (id, a) in [('q1', ['y', 'n', 'rn']), ('q2', ['y', 'n', 'ns']), ('q3', ['y', 'n', 'ns']), ('q4', ['y', 'n', 'ns']),
            ('q5', ['y', 'n', 'rn']), ('q6', ['y', 'n', 'rn'])])
            {'id': id, 'answers': a}
        ];
  }

  Map<String, dynamic> _scoreLocally(AppState s) {
    final cfg = (s.bundle?['check'] as Map<String, dynamic>?) ??
        {'scoring': {'q1': {'y': 2}, 'q2': {'n': 1, 'ns': 1}, 'q3': {'n': 1, 'ns': 1}, 'q6': {'y': 2}}, 'threshold_next': 2,
          'flags': {'sti_signs': {'q4': 'y'}, 'safeguarding': {'q5': 'y'}}};
    int score = 0;
    final scoring = (cfg['scoring'] as Map).cast<String, dynamic>();
    answers.forEach((q, a) {
      if (a != 'rn') score += ((scoring[q] as Map?)?[a] as int?) ?? 0;
    });
    final flags = (cfg['flags'] as Map).cast<String, dynamic>();
    bool flag(String n) => (flags[n] as Map).entries.any((e) => answers[e.key] == e.value);
    final band = score >= (cfg['threshold_next'] as int? ?? 2) ? 'next' : 'low';
    return {'band': band, 'sti': flag('sti_signs'), 'safeguarding': flag('safeguarding')};
  }

  Future<void> _finish(AppState s) async {
    final local = _scoreLocally(s);
    setState(() {
      result = local;
      i = _questions(s).length;
    });
    try {
      final res = await s.api.post('/v1/learner/check', {'answers': answers, 'lang': s.lang, 'tier': s.tier}) as Map<String, dynamic>;
      if (res['crisis'] != null) s.pendingCrisis = res['crisis'];
    } catch (_) {/* offline: result shown from local scoring, nothing queued */}
    answers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;
    final qs = _questions(s);
    List<Widget> body;
    if (i < 0) {
      body = [
        Text(s.t('menu', 'row_check'), style: tt.headlineSmall),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.t('check', 'intro'), style: tt.bodyLarge))),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: DraftChip()),
        const SizedBox(height: 20),
        FilledButton(key: const Key('check-start'), onPressed: () {
          s.api.post('/v1/learner/events', {'event': 'check_started', 'lang': s.lang, 'tier': s.tier}).catchError((_) => null);
          setState(() => i = 0);
        }, child: Text(s.t('check', 'btn_start'))),
      ];
    } else if (i < qs.length) {
      final q = qs[i];
      body = [
        LinearProgressIndicator(value: (i + 1) / qs.length, color: c.primary, backgroundColor: c.line, minHeight: 6,
            borderRadius: BorderRadius.circular(3)),
        const SizedBox(height: 16),
        Text(s.t('check', 'progress', {'n': '${i + 1}'}), style: tt.labelLarge?.copyWith(color: c.primary)),
        const SizedBox(height: 8),
        Text(s.t('check', q['id']), style: tt.headlineSmall),
        if (showQ5Support) ...[
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.support, width: 2)),
            child: Padding(padding: const EdgeInsets.all(14), child: Text(s.t('check', 'q5_yes'))),
          ),
        ],
        const SizedBox(height: 20),
        for (final a in (q['answers'] as List).cast<String>()) ...[
          OutlinedButton(
            key: Key('ans-${q['id']}-$a'),
            onPressed: () {
              answers[q['id']] = a;
              final q5 = q['id'] == 'q5' && a == 'y';
              setState(() => showQ5Support = q5);
              if (q5) return; // show the support line, then continue with the button below
              if (i + 1 >= qs.length) {
                _finish(s);
              } else {
                setState(() => i++);
              }
            },
            child: Text(s.t('check', _labelKey[a]!)),
          ),
          const SizedBox(height: 10),
        ],
        if (showQ5Support)
          FilledButton(onPressed: () => setState(() {
                showQ5Support = false;
                i++;
              }), child: const Icon(Icons.arrow_forward)),
      ];
    } else {
      final r = result!;
      body = [
        Text(s.t('app', 'result_title'), style: tt.headlineSmall),
        const SizedBox(height: 12),
        if (r['sti'] == true)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.t('check', 'result_sti'), style: tt.bodyLarge))),
        if (r['sti'] == true) const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s.t('check', r['band'] == 'next' ? 'result_next' : 'result_low'), style: tt.bodyLarge),
          ),
        ),
        const SizedBox(height: 6),
        const Align(alignment: Alignment.centerLeft, child: DraftChip()),
        const NotMedicalAdvice(),
        const SizedBox(height: 20),
        FilledButton(key: const Key('check-find'), onPressed: () => context.pushReplacement('/services'), child: Text(s.t('check', 'btn_find'))),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => _selfTest(context, s), child: Text(s.t('check', 'btn_selftest'))),
        if (r['safeguarding'] == true) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.support, foregroundColor: c.onSupport),
            onPressed: () {
              s.showCrisis(s.pendingCrisis ?? {'type': 'crisis', 'crisis': 'sexual_violence', 'refs': [['crisis', 'violence'], ['crisis', 'pep']]});
              context.push('/crisis');
            },
            icon: const Icon(Icons.favorite_border),
            label: Text(s.t('crisis', 'btn_call')),
          ),
        ],
      ];
    }
    return NsScaffold(title: s.t('menu', 'row_check'), body: NsPage(maxWidth: 560, children: body));
  }

  void _selfTest(BuildContext context, AppState s) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t('check', 'selftest'), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
          const DraftChip(),
        ]),
      ),
    );
  }
}
