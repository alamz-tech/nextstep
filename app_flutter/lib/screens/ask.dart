import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/recorder.dart';
import '../core/state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// Ask a question by text or hold-to-talk voice. Answers are grounded in the
/// reviewed knowledge base and show their sources. Needs a connection.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});
  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _rec = VoiceRecorder();
  final _player = AudioPlayer();
  late List<Map<String, dynamic>> items;
  bool busy = false, recording = false, offline = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    items = s.keepHistory ? List.of(s.history) : [];
  }

  @override
  void dispose() {
    _rec.cancel();
    _rec.dispose();
    _player.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _handle(AppState s, Future<dynamic> Function() call, Map<String, dynamic> userItem) async {
    setState(() {
      busy = true;
      offline = false;
      items.add(userItem);
    });
    _scrollDown();
    try {
      final res = (await call()) as Map<String, dynamic>;
      if (res['transcript'] != null) {
        items.last = {'from': 'user', 'text': res['transcript'], 'voice': true};
      }
      if (res['type'] == 'crisis') {
        s.showCrisis(res);
        if (mounted) context.push('/crisis');
      }
      final item = {'from': 'bot', ...res};
      setState(() => items.add(item));
      if (s.keepHistory) {
        await s.addHistory(items[items.length - 2]);
        await s.addHistory(item);
      }
      if (res['audio_url'] != null && !s.lowData) {
        _player.play(UrlSource(s.api.absolute(res['audio_url'])));
      }
    } on OfflineException {
      setState(() {
        offline = true;
        items.removeLast();
      });
    } catch (_) {
      setState(() => items.add({'from': 'bot', 'type': 'error', 'text': s.t('app', 'error_generic')}));
    } finally {
      if (mounted) setState(() => busy = false);
      _scrollDown();
    }
  }

  Future<void> _sendText(AppState s) async {
    final q = _ctl.text.trim();
    if (q.isEmpty || busy) return;
    _ctl.clear();
    await _handle(s, () => s.api.post('/v1/learner/ask', {'question': q, 'lang': s.lang, 'tier': s.tier, 'want_audio': !s.lowData}),
        {'from': 'user', 'text': q});
  }

  Future<void> _startRec(AppState s) async {
    if (busy) return;
    final ok = await _rec.start();
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('app', 'mic_unavailable'))));
      return;
    }
    setState(() => recording = true);
  }

  Future<void> _stopRec(AppState s) async {
    if (!recording) return;
    setState(() => recording = false);
    final r = await _rec.stop();
    if (r == null) return;
    final (bytes, name) = r;
    await _handle(s, () => s.api.postAudio('/v1/learner/ask/voice', bytes, name,
        {'lang': s.lang, 'tier': s.tier, 'want_audio': (!s.lowData).toString()}), {'from': 'user', 'text': '…', 'voice': true});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    return NsScaffold(
      title: s.t('menu', 'row_ask'),
      body: Column(children: [
        if (offline)
          MaterialBanner(
            backgroundColor: c.supportTint,
            content: Text(s.t('app', 'offline_ask')),
            actions: [TextButton(onPressed: () => setState(() => offline = false), child: const Text('OK'))],
          ),
        Expanded(
          child: Container(
            color: c.chatBg,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
                  Bubble(child: Text(s.t('qa', 'prompt'))),
                  for (final it in items) _item(context, s, it),
                  if (busy) Bubble(child: Text(s.t('app', 'thinking'), style: TextStyle(color: c.text2))),
                ]),
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
          padding: const EdgeInsets.all(10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('ask-input'),
                    controller: _ctl,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendText(s),
                    decoration: InputDecoration(hintText: s.t('app', 'ask_placeholder'), counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: recording ? s.t('app', 'release_to_send') : s.t('app', 'hold_to_talk'),
                  child: GestureDetector(
                    key: const Key('hold-to-talk'),
                    onLongPressStart: (_) => _startRec(s),
                    onLongPressEnd: (_) => _stopRec(s),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('app', 'hold_to_talk')))),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: recording ? 60 : 48,
                      height: recording ? 60 : 48,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: recording ? c.accent : c.surface, border: Border.all(color: c.primary, width: 2)),
                      child: Icon(Icons.mic_none, color: recording ? c.onAccent : c.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(key: const Key('ask-send'), onPressed: busy ? null : () => _sendText(s), child: Text(s.t('app', 'send'))),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _item(BuildContext context, AppState s, Map<String, dynamic> it) {
    final c = NsColors.of(context);
    if (it['from'] == 'user') {
      return Bubble(
        user: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (it['voice'] == true) ...[Icon(Icons.mic_none, size: 18, color: c.text2), const SizedBox(width: 6)],
          Flexible(child: Text(it['text'] ?? '')),
        ]),
      );
    }
    final type = it['type'];
    final safety = type == 'crisis';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Bubble(
        safety: safety,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (it['audio_url'] != null)
            TextButton.icon(
              onPressed: () => _player.play(UrlSource(s.api.absolute(it['audio_url']))),
              icon: const Icon(Icons.play_arrow),
              label: Text(s.t('app', 'play')),
            ),
          Text(it['text'] ?? ''),
          if (type == 'answer') SourcesLine(sources: (it['sources'] as List?) ?? []),
          if (type != 'error') const NotMedicalAdvice(),
        ]),
      ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (it['draft'] == true) const DraftChip(),
        if (safety) const Chip2('Safety response', bg: Color(0xFF2F5DA8), fg: Colors.white),
        if (it['voice_fallback'] == true) Text('Voice reply off for this language (text only)', style: TextStyle(fontSize: 12, color: c.text2)),
      ]),
      if (type == 'unknown' || type == 'out_of_scope' || type == 'answer')
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: () => context.push('/services'), child: Text(s.t('qa', 'btn_find'))),
          ]),
        ),
    ]);
  }
}
