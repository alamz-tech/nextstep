import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Shown whenever the safety layer detects a crisis. Calm wording from the design
/// copy; contacts come only from verified config (placeholders until filled).
class CrisisScreen extends StatelessWidget {
  const CrisisScreen({super.key, required this.payload, this.onDone, this.showQuickExit = true});
  final Map<String, dynamic> payload;
  final VoidCallback? onDone;
  final bool showQuickExit;

  static final _phone = RegExp(r'\+?\d[\d\s-]{2,}\d');

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final refs = (payload['refs'] as List?)?.cast<List>() ?? [];
    final texts = refs.isNotEmpty ? refs.map((r) => s.t(r[0], r[1])).toList() : [payload['text'] as String? ?? ''];
    final numbers = texts.expand((t) => _phone.allMatches(t).map((m) => m.group(0)!)).toSet().toList();
    return NsScaffold(
      title: s.t('app', 'crisis_title'),
      quickExit: showQuickExit,
      body: NsPage(children: [
        for (final t in texts)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.support, width: 2)),
            child: Padding(padding: const EdgeInsets.all(18), child: Text(t, style: Theme.of(context).textTheme.bodyLarge)),
          ),
        const SizedBox(height: 8),
        const Align(alignment: Alignment.centerLeft, child: Chip2('Safety response', bg: Color(0xFF2F5DA8), fg: Colors.white)),
        const SizedBox(height: 16),
        for (final n in numbers) ...[
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: c.support, foregroundColor: c.onSupport),
            onPressed: () => launchUrl(Uri.parse('tel:${n.replaceAll(RegExp(r'[\s-]'), '')}')),
            icon: const Icon(Icons.phone),
            label: Text('${s.t('app', 'call')} $n'),
          ),
          const SizedBox(height: 8),
        ],
        if (numbers.isEmpty)
          Text('Helpline numbers appear here once verified contacts are configured.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('crisis-safe'),
          onPressed: () {
            s.pendingCrisis = null;
            if (onDone != null) {
              onDone!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
          child: Text(s.t('crisis', 'btn_safe')),
        ),
      ]),
    );
  }
}
