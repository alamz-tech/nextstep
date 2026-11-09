import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'crisis.dart';

/// Student question box. Opened from the facilitator's QR code in a browser:
/// no install, no login, no name. Crisis detection runs on every question.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.code});
  final String code;
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _ctl = TextEditingController();
  Map<String, dynamic>? info;
  String? status, message, error;
  Map<String, dynamic>? crisis;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final r = await s.api.get('/v1/join/${widget.code}') as Map<String, dynamic>;
      if (r['lang'] != null && !s.onboarded) await s.setLang(r['lang']);
      setState(() => info = r);
      if (r['open'] == true) s.api.post('/v1/join/${widget.code}/hello').catchError((_) => null);
    } on ApiException {
      setState(() => error = s.t('app', 'join_closed'));
    } on OfflineException {
      setState(() => error = s.t('app', 'offline_ask'));
    }
  }

  Future<void> _send(AppState s) async {
    final q = _ctl.text.trim();
    if (q.isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await s.api.post('/v1/join/${widget.code}/questions', {'text': q}) as Map<String, dynamic>;
      _ctl.clear();
      setState(() {
        status = r['status'];
        message = r['text'];
        crisis = r['crisis'];
      });
    } on ApiException catch (e) {
      setState(() => error = e.status == 429 ? 'Please wait a minute before sending another question.' : s.t('app', 'join_closed'));
    } on OfflineException {
      setState(() => error = s.t('app', 'offline_ask'));
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;
    if (crisis != null) {
      return CrisisScreen(payload: crisis!, showQuickExit: false, onDone: () => setState(() {
            crisis = null;
            status = null;
          }));
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const Logo(size: 30), const SizedBox(width: 10), Text(s.t('app', 'join_title'))]),
        actions: [
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('EN')), ButtonSegment(value: 'pcm', label: Text('Pidgin'))],
            selected: {s.lang},
            showSelectedIcon: false,
            onSelectionChanged: (v) => s.setLang(v.first),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: NsPage(maxWidth: 520, children: [
          if (error != null) Text(error!, style: tt.titleMedium)
          else if (info == null) const Center(child: CircularProgressIndicator())
          else if (info!['open'] != true) Text(s.t('app', 'join_closed'), style: tt.titleMedium)
          else if (status != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Icon(status == 'received' ? Icons.check_circle_outline : Icons.info_outline, color: status == 'received' ? c.success : c.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(message ?? '', style: tt.bodyLarge)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const Key('join-another'), onPressed: () => setState(() => status = null), child: Text(s.t('app', 'join_another'))),
          ] else ...[
            Text(s.t('app', 'join_body'), style: tt.bodyLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('join-input'),
              controller: _ctl,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(hintText: s.t('app', 'join_placeholder')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('join-send'),
              onPressed: busy ? null : () => _send(s),
              icon: const Icon(Icons.send),
              label: Text(s.t('app', 'join_send')),
            ),
            const SizedBox(height: 16),
            Text('NextStep · ${s.t('app', 'not_medical_advice')}', style: tt.bodySmall),
          ],
        ]),
      ),
    );
  }
}
