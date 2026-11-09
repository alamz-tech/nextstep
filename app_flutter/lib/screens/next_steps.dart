import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Saved referral codes (on this device only), reminder settings and outcome buttons.
class NextStepsScreen extends StatefulWidget {
  const NextStepsScreen({super.key});
  @override
  State<NextStepsScreen> createState() => _NextStepsScreenState();
}

class _NextStepsScreenState extends State<NextStepsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().syncConfirmations();
  }

  Future<void> _outcome(AppState s, SavedReferral r, String o) async {
    if (o == 'need_help') {
      final barrier = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(12), child: Text(s.t('followup', 'help'), style: Theme.of(ctx).textTheme.titleLarge)),
            for (final (k, row) in [('cost', 'row_cost'), ('scared', 'row_scared'), ('blocked', 'row_blocked'), ('other', 'row_other')])
              ListTile(
                title: Text(s.t('followup', row)),
                subtitle: Text(s.t('followup', '${row}_desc')),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ]),
        ),
      );
      if (barrier == null) return;
      final res = await s.recordOutcome(r, o, barrier: barrier);
      if (!mounted) return;
      final msg = {'cost': 'help_cost', 'scared': 'help_scared', 'blocked': 'help_blocked'}[barrier];
      if (barrier == 'blocked') {
        s.showCrisis(res?['crisis'] ?? {'type': 'crisis', 'crisis': 'violence', 'refs': [['crisis', 'violence']]});
        context.push('/crisis');
      } else if (barrier == 'other') {
        context.push('/ask');
      } else if (msg != null) {
        showDialog(context: context, builder: (ctx) => AlertDialog(content: Text(s.t('followup', msg)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
      }
      return;
    }
    await s.recordOutcome(r, o);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(o == 'went' ? s.t('followup', 'yes') : s.t('followup', 'not_yet'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;
    return NsScaffold(
      title: s.t('app', 'next_title'),
      body: NsPage(children: [
        if (s.referrals.isEmpty) ...[
          Text(s.t('app', 'no_codes'), style: tt.bodyLarge),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => context.pushReplacement('/services'), child: Text(s.t('menu', 'row_find'))),
        ],
        for (final r in s.referrals)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(r.code, style: TextStyle(fontFamily: kDisplay, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4, color: c.primary)),
                    const Spacer(),
                    if (r.confirmed) Chip2(s.t('app', 'confirmed'), bg: c.success, fg: Colors.white),
                  ]),
                  Text(r.serviceName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(r.area, style: tt.bodySmall),
                  if (r.demo) ...[const SizedBox(height: 6), const DemoTag()],
                  const Divider(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: r.reminders,
                    onChanged: r.outcome == 'went' ? null : (v) => s.setReminders(r, v),
                    title: Text(s.t('app', 'reminder_toggle')),
                    subtitle: Text(kIsWeb ? '${s.t('app', 'reminder_note')} (Android app only)' : s.t('app', 'reminder_note')),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t('app', 'outcome_q'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final (o, label) in [('went', 'btn_yes'), ('not_yet', 'btn_not_yet'), ('need_help', 'btn_help')])
                      ChoiceChip(
                        key: Key('outcome-${r.code}-$o'),
                        label: Text(s.t('followup', label)),
                        selected: r.outcome == o,
                        onSelected: (_) => _outcome(s, r, o),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
