import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../widgets/chat_ui.dart';

/// Student question box, opened from the facilitator's QR code: same chat look,
/// no install, no login, no name. Crisis detection runs on every question.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.code});
  final String code;
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _ctl = TextEditingController();
  final List<(String from, Map d)> items = [];
  bool? open;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final r = await s.api.get('/v1/join/${widget.code}') as Map<String, dynamic>;
      s.lang = r['lang'] ?? s.lang;
      setState(() => open = r['open'] == true);
      if (open == true) s.api.post('/v1/join/${widget.code}/hello').catchError((_) => null);
    } catch (_) {
      setState(() => open = false);
    }
  }

  Future<void> _send(AppState s) async {
    final q = _ctl.text.trim();
    if (q.isEmpty || busy) return;
    _ctl.clear();
    setState(() {
      busy = true;
      items.add(('user', {'text': q}));
    });
    try {
      final r = await s.api.post('/v1/join/${widget.code}/questions', {'text': q}) as Map<String, dynamic>;
      setState(() {
        if (r['status'] == 'crisis') {
          for (final ref in (r['crisis']['refs'] as List)) {
            items.add(('bot', {'ref': ref, 'safety': true, 'draft': true}));
          }
        } else {
          items.add(('bot', {'text': r['text']}));
        }
      });
    } on ApiException catch (e) {
      setState(() => items.add(('sys', {'ref': e.status == 404 ? ['app', 'join_closed'] : ['app', 'offline']})));
    } on OfflineException {
      setState(() => items.add(('sys', {'ref': ['app', 'offline']})));
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String tx(Map d) => d['text'] ?? s.t(d['ref'] as List);
    final hasText = _ctl.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: W.bg,
      appBar: chatHeader(menu: const [], onMenu: (_) {}),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.fromLTRB(10, 12, 10, 16), children: [
                  if (open == false) SysPill(s.t(['app', 'join_closed'])),
                  if (open == true) BotBubble(text: '${s.t(['app', 'join_title'])}\n\n${s.t(['app', 'join_body'])}'),
                  for (final (from, d) in items)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: from == 'user'
                          ? UserBubble(tx(d))
                          : from == 'sys'
                              ? SysPill(tx(d))
                              : BotBubble(text: tx(d), safety: d['safety'] == true, draft: d['draft'] == true),
                    ),
                ]),
              ),
            ),
          ),
          if (open == true)
            Container(
              color: W.bg,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Row(children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          key: const Key('join-input'),
                          controller: _ctl,
                          maxLength: 500,
                          onSubmitted: (_) => _send(s),
                          decoration: InputDecoration(hintText: s.t(['sim', 'placeholder']), border: InputBorder.none, counterText: '',
                              hintStyle: const TextStyle(color: W.sub), contentPadding: const EdgeInsets.symmetric(vertical: 11)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      key: const Key('join-send'),
                      customBorder: const CircleBorder(),
                      onTap: hasText ? () => _send(s) : null,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: hasText ? W.berry : W.berry.withValues(alpha: 0.5), shape: BoxShape.circle),
                        child: Semantics(label: s.t(['app', 'join_send']), child: const Icon(Icons.send, color: Colors.white, size: 20)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
