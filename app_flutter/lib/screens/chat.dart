import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/recorder.dart';
import '../core/state.dart';
import '../widgets/chat_ui.dart';

/// The learner app: one chat screen, built to the design's WhatsApp-style chat frame.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  final _rec = VoiceRecorder();
  final _player = AudioPlayer();
  bool recording = false;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().start());
  }

  @override
  void dispose() {
    _rec.cancel();
    _rec.dispose();
    _player.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _play(String dataUri) async {
    final bytes = base64Decode(dataUri.split(',').last);
    await _player.play(kIsWeb ? UrlSource(dataUri) : BytesSource(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.msgs.length != _seen) {
      _seen = s.msgs.length;
      _toBottom();
      final last = s.msgs.isNotEmpty ? s.msgs.last.data : null;
      if (last?['audio'] != null) _play(last!['audio']);
    }
    var lastActive = -1;
    for (var i = 0; i < s.msgs.length; i++) {
      final d = s.msgs[i].data;
      if (s.msgs[i].from == 'bot' && ((d['buttons'] as List?)?.isNotEmpty == true || d['list'] != null)) lastActive = i;
    }
    final demo = s.demoMode;
    return Scaffold(
      backgroundColor: W.bg,
      appBar: chatHeader(
        menu: [PopupMenuItem(key: const Key('quick-exit'), value: 'exit', child: Text(s.t(['app', 'quick_exit'])))],
        onMenu: (v) {
          if (v == 'exit') s.quickExit();
        },
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
                  children: [
                    if (demo) SysPill(s.t(['sim', 'banner']), yellow: true),
                    for (var i = 0; i < s.msgs.length; i++)
                      Padding(padding: const EdgeInsets.only(top: 8), child: _msg(context, s, s.msgs[i], i == lastActive && !s.busy)),
                    if (s.offline) Padding(padding: const EdgeInsets.only(top: 8), child: SysPill(s.t(['app', 'offline']))),
                  ],
                ),
              ),
            ),
          ),
          _composer(s, demo),
        ]),
      ),
    );
  }

  Widget _composer(AppState s, bool demo) {
    final hasText = _ctl.text.trim().isNotEmpty;
    return Container(
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
                  key: const Key('chat-input'),
                  controller: _ctl,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(s),
                  style: const TextStyle(fontSize: 15, color: W.ink),
                  decoration: InputDecoration(
                    hintText: s.t(['sim', 'placeholder']),
                    hintStyle: const TextStyle(color: W.sub, fontSize: 15),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: hasText ? s.t(['sim', 'send']) : s.t(['sim', 'voice']),
              child: GestureDetector(
                key: const Key('chat-send'),
                onTap: () {
                  if (hasText) {
                    _send(s);
                  } else {
                    // Tapping the mic never sends anything: hold to record, release to send.
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(SnackBar(content: Text(s.t(['app', 'hold_to_record'])), duration: const Duration(seconds: 2)));
                  }
                },
                onLongPressStart: hasText ? null : (_) => _startRec(),
                onLongPressEnd: hasText ? null : (_) => _stopRec(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: recording ? 56 : 46,
                  height: recording ? 56 : 46,
                  decoration: BoxDecoration(color: recording ? W.berryDeep : W.berry, shape: BoxShape.circle),
                  child: Icon(hasText ? Icons.send : Icons.mic_none, color: Colors.white, size: 20),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _send(AppState s) {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    _ctl.clear();
    s.sendText(t);
  }

  Future<void> _startRec() async {
    if (await _rec.start()) setState(() => recording = true);
  }

  Future<void> _stopRec(AppState s) async {
    if (!recording) return;
    setState(() => recording = false);
    final r = await _rec.stop();
    if (r != null) await s.sendVoice(r.$1, r.$2);
  }

  String _text(AppState s, Map d) {
    if (d['texts'] != null) {
      final m = d['texts'] as Map;
      return (m[s.lang] ?? m['en'] ?? m.values.first ?? '') as String;
    }
    if (d['ref'] != null) return s.t(d['ref'] as List, d['params'] as Map?);
    return '';
  }

  Widget _msg(BuildContext context, AppState s, Msg m, bool active) {
    final d = m.data;
    if (m.from == 'sys') return SysPill(_text(s, d));
    if (m.from == 'user') {
      if (d['voice'] == true) return UserVoiceBubble(transcript: _text(s, d));
      return UserBubble(_text(s, d));
    }
    switch (d['kind']) {
      case 'call':
        return BotBubble(text: '', safety: true, buttons: [
          ReplyRow(label: d['number'], icon: Icons.call,
              onTap: () => launchUrl(Uri.parse('tel:${(d['number'] as String).replaceAll(RegExp(r'[\s-]'), '')}'))),
        ]);
      case 'url':
        return BotBubble(text: s.t(['referral', 'intro']), buttons: [
          ReplyRow(label: s.t(d['ref']), icon: Icons.open_in_new, onTap: () => launchUrl(Uri.parse(d['url']))),
        ]);
    }
    final buttons = <Widget>[
      if (d['list'] != null)
        ReplyRow(
          label: s.t(['global', 'list_button']),
          icon: Icons.menu,
          onTap: active
              ? () async {
                  final rows = (d['list'] as List).cast<Map>();
                  final pick = await showListSheet(context, title: s.t(['global', 'list_button']), rows: [
                    for (final r in rows) (r['id'] as String, s.t(r['ref']), s.t(r['desc_ref'])),
                  ]);
                  if (pick != null) {
                    final r = rows.firstWhere((r) => r['id'] == pick);
                    s.tapButton(pick, r['ref']);
                  }
                }
              : null,
        ),
      for (final b in ((d['buttons'] as List?) ?? []).cast<Map>())
        ReplyRow(key: Key('btn-${b['id']}'), label: s.t(b['ref']), onTap: active ? () => s.tapButton(b['id'], b['ref']) : null),
    ];
    Widget? card;
    var text = _text(s, d);
    if (d['kind'] == 'card') {
      final c = d['card'] as Map;
      card = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ServiceCardTop(
          free: c['is_free'] == true ? s.t(['referral', 'tag_free']) : null,
          youth: c['youth_friendly'] == true ? s.t(['referral', 'tag_youth']) : null,
          label: s.t(['referral', 'card_image_label']),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 15, height: 20 / 15, color: W.ink),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c['demo_tag_ref'] != null)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Tag(s.t(c['demo_tag_ref']), bg: const Color(0xFFC2462E), fg: Colors.white)),
              Text(c['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.place_outlined, size: 18, color: W.berry),
                const SizedBox(width: 6),
                Expanded(child: Text(c['address'])),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.schedule, size: 18, color: W.berry),
                const SizedBox(width: 6),
                Expanded(child: Text(c['hours_raw'])),
              ]),
              if (c['code'] != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.confirmation_number_outlined, size: 18, color: W.berry),
                  const SizedBox(width: 6),
                  SelectableText(c['code'], key: const Key('referral-code'),
                      style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 16)),
                ]),
              ],
              const SizedBox(height: 10),
              Text(s.t(['referral', 'expect_title']), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]);
    }
    final kicker = d['kicker'] != null ? s.t(['check', 'progress'], {'n': '${d['kicker']}'}) : null;
    final bubble = BotBubble(text: text, kicker: kicker, card: card, buttons: buttons, draft: d['draft'] == true, safety: d['safety'] == true);
    if (d['audio'] != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BotVoiceBubble(label: s.t(['qa', 'voice_label']), onPlay: () => _play(d['audio'])),
        const SizedBox(height: 8),
        bubble,
      ]);
    }
    return bubble;
  }
}
