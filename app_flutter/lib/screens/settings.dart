import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'pin_pad.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setPin(BuildContext context, AppState s) async {
    String? first;
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(first == null ? s.t('app', 'pin_title') : s.t('app', 'pin_again')),
          content: SingleChildScrollView(
            child: PinPad(
              key: ValueKey(first),
              onComplete: (p) {
                if (first == null) {
                  set(() => first = p);
                } else {
                  Navigator.pop(ctx, p == first ? p : null);
                }
              },
            ),
          ),
        ),
      ),
    );
    if (pin != null) await s.setPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    return NsScaffold(
      title: s.t('app', 'settings_title'),
      body: NsPage(children: [
        ListTile(
          title: Text(s.t('app', 'language')),
          trailing: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'pcm', label: Text('Pidgin'))],
            selected: {s.lang},
            showSelectedIcon: false,
            onSelectionChanged: (v) => s.setLang(v.first),
          ),
        ),
        SwitchListTile(
          key: const Key('pin-toggle'),
          title: Text(s.t('app', 'pin_lock')),
          value: s.hasPin,
          onChanged: (v) => v ? _setPin(context, s) : s.setPin(null),
        ),
        SwitchListTile(
          title: Text(s.t('app', 'low_data')),
          subtitle: Text(s.t('app', 'low_data_desc')),
          value: s.lowData,
          onChanged: s.setLowData,
        ),
        SwitchListTile(
          title: Text(s.t('app', 'keep_history')),
          subtitle: Text(s.t('app', 'keep_history_desc')),
          value: s.keepHistory,
          onChanged: s.setKeepHistory,
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: Text(s.t('app', 'staff_signin')),
          onTap: () => context.push('/staff'),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(s.t('app', 'about')),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'NextStep',
            applicationVersion: '0.2 prototype',
            applicationLegalese: 'Alamz Tech Ltd. Code: MIT. Content: CC BY 4.0. All health content is draft pending clinician review.',
          ),
        ),
        const Divider(height: 32),
        FilledButton.icon(
          key: const Key('delete-data'),
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
          icon: const Icon(Icons.delete_forever_outlined),
          label: Text(s.t('app', 'delete')),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(s.t('app', 'delete')),
                content: Text(s.t('app', 'delete_confirm')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('app', 'cancel'))),
                  FilledButton(key: const Key('delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('app', 'delete'))),
                ],
              ),
            );
            if (ok == true) {
              final msg = s.t('global', 'delete');
              final messenger = ScaffoldMessenger.of(context);
              final serverOk = await s.deleteEverything();
              messenger.showSnackBar(SnackBar(content: Text(serverOk ? msg : '$msg (server: retry when online)')));
              if (context.mounted) context.go('/');
            }
          },
        ),
      ]),
    );
  }
}
