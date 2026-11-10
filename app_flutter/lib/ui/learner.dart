import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../widgets/chat_ui.dart';
import 'kit.dart';

/// Learner screens. Home is the hub; every inner screen has a back arrow to Home and quick exit.

Widget _exit(BuildContext context) {
  final s = context.read<AppState>();
  return quickExitIcon(s.quickExit, s.t(['app', 'quick_exit']));
}

void _home(BuildContext context) => context.go('/');

Widget _offline(AppState s) => Padding(padding: const EdgeInsets.only(top: 8), child: SysPill(s.t(['app', 'offline'])));

/// "/": first-time setup until done, then Home.
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});
  @override
  Widget build(BuildContext context) => context.watch<AppState>().setupDone ? const HomeScreen() : const SetupScreen();
}

// ===================================================================== first-time setup
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int step = 0; // 0 consent, 1 age, 2 language, 9 under-15 exit
  String tier = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String t(String f, String k) => s.t([f, k]);
    final bar = nsBar(title: 'NextStep', brand: true);
    switch (step) {
      case 0:
        return Scaffold(
          appBar: bar,
          body: NsBody(
            bottom: PrimaryButton(t('consent', 'btn_agree'), key: const Key('consent-agree'), onPressed: () => setState(() => step = 1)),
            children: [Panel(child: Text(t('consent', 'body'), style: bodyText))],
          ),
        );
      case 1:
        return Scaffold(
          appBar: bar,
          body: NsBody(children: [
            Text(t('age', 'ask'), style: titleText),
            const SizedBox(height: 16),
            for (final (k, label) in [('15_17', 'btn_15_17'), ('18_24', 'btn_18_24')])
              ChoiceButton(t('age', label), key: Key('age-$k'), onPressed: () => setState(() {
                    tier = k;
                    step = 2;
                  })),
            ChoiceButton(t('age', 'btn_under15'), key: const Key('age-under_15'), onPressed: () {
              s.under15();
              setState(() => step = 9);
            }),
          ]),
        );
      case 9:
        return Scaffold(appBar: bar, body: NsBody(children: [Panel(border: W.berry, child: Text(t('age', 'under15'), style: bodyText))]));
      default:
        return Scaffold(
          appBar: bar,
          body: NsBody(children: [
            Text(t('menu', 'lang_prompt'), style: titleText),
            const SizedBox(height: 16),
            for (final (l, label) in [('en', 'btn_en'), ('pcm', 'btn_pcm')])
              ChoiceButton(t('menu', label), key: Key('lang-$l'), onPressed: () => s.finishSetup(tier, l)),
          ]),
        );
    }
  }
}

// ===================================================================== PIN
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onComplete});
  final void Function(String) onComplete;
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String pin = '';
  void _tap(String d) {
    if (d == '⌫') {
      setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1));
      return;
    }
    if (pin.length >= 4) return;
    setState(() => pin += d);
    if (pin.length == 4) {
      final p = pin;
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => pin = '');
        widget.onComplete(p);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 4; i++)
            Container(margin: const EdgeInsets.all(8), width: 14, height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? W.berry : Colors.white)),
        ]),
        const SizedBox(height: 12),
        for (final row in [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9'], ['', '0', '⌫']])
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final d in row)
              Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  width: 76,
                  height: 56,
                  child: d.isEmpty
                      ? null
                      : OutlinedButton(
                          key: Key('pin-$d'),
                          style: OutlinedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: W.ink,
                              side: const BorderSide(color: W.btnLine), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () => _tap(d),
                          child: Text(d, style: const TextStyle(fontSize: 22)),
                        ),
                ),
              ),
          ]),
      ]);
}

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  bool wrong = false;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: nsBar(title: 'NextStep', brand: true),
      body: NsBody(children: [
        Center(child: Text(s.t(['app', wrong ? 'pin_wrong' : 'unlock_title']), style: titleText)),
        const SizedBox(height: 12),
        PinPad(onComplete: (p) => setState(() => wrong = !s.unlockWithPin(p))),
      ]),
    );
  }
}

// ===================================================================== Home
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String t(String f, String k) => s.t([f, k]);
    final code = s.activeCode;
    return Scaffold(
      appBar: nsBar(title: 'NextStep', brand: true, actions: [
        _exit(context),
        IconButton(key: const Key('settings'), tooltip: t('app', 'settings_title'), onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.settings_outlined, color: W.ink)),
      ]),
      body: NsBody(children: [
        RowGroup(rows: [
          NsRow(key: const Key('home-ask'), title: t('menu', 'row_ask'), subtitle: t('menu', 'row_ask_desc'), onTap: () => context.go('/ask')),
          NsRow(key: const Key('home-check'), title: t('menu', 'row_check'), subtitle: t('menu', 'row_check_desc'), onTap: () => context.go('/check')),
          NsRow(key: const Key('home-find'), title: t('menu', 'row_find'), subtitle: t('menu', 'row_find_desc'), onTap: () => context.go('/services')),
        ]),
        if (code != null) ...[
          const SizedBox(height: 16),
          Panel(
            child: InkWell(
              key: const Key('home-code'),
              onTap: () => context.go('/code/${code.code}'),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('app', 'code_title'), style: const TextStyle(fontSize: 13, color: W.sub)),
                    Text(code.code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3, color: W.berry)),
                    Text('${code.serviceName} · ${code.area}', style: const TextStyle(fontSize: 13, color: W.sub)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: W.sub),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// ===================================================================== Private check
class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});
  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> {
  List<Map<String, dynamic>>? qs;
  int i = 0;
  final Map<String, String> answers = {};
  Map<String, dynamic>? result;
  bool offline = false, sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final r = await s.api.get('/v1/learner/check', q: {'lang': s.lang}) as Map<String, dynamic>;
      setState(() => qs = (r['questions'] as List).cast<Map<String, dynamic>>());
    } catch (_) {
      setState(() => offline = true);
    }
  }

  Future<void> _answer(AppState s, String qid, String a) async {
    answers[qid] = a;
    if (i + 1 < qs!.length) {
      setState(() => i++);
      return;
    }
    setState(() => sending = true);
    try {
      final r = await s.api.post('/v1/learner/check', {'answers': answers, 'lang': s.lang, 'tier': s.tier}) as Map<String, dynamic>;
      answers.clear(); // never kept
      setState(() => result = r);
      if (r['crisis'] != null && mounted) {
        s.pendingCrisis = r['crisis'];
        context.push('/crisis');
      }
    } catch (_) {
      setState(() => offline = true);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final bar = nsBar(title: s.t(['menu', 'row_check']), onBack: () => _home(context), actions: [_exit(context)]);
    if (result != null) {
      return Scaffold(
        appBar: bar,
        body: NsBody(
          bottom: PrimaryButton(s.t(['check', 'btn_find']), key: const Key('check-find'), onPressed: () => context.go('/services')),
          children: [
            if ((result!['sti_text'] as String? ?? '').isNotEmpty) ...[
              Panel(child: Text(result!['sti_text'], style: bodyText)),
              const SizedBox(height: 10),
            ],
            Panel(child: Text(result!['text'], style: bodyText)),
          ],
        ),
      );
    }
    if (qs == null) {
      return Scaffold(appBar: bar, body: NsBody(children: [if (offline) _offline(s) else const Center(child: CircularProgressIndicator(color: W.berry))]));
    }
    final q = qs![i];
    return Scaffold(
      appBar: bar,
      body: NsBody(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: (i + 1) / qs!.length, minHeight: 6, color: W.berry, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(s.t(['check', 'progress'], {'n': '${i + 1}'}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: W.berry)),
        const SizedBox(height: 12),
        Text(q['text'], style: titleText),
        const SizedBox(height: 20),
        for (final a in (q['answers'] as List).cast<Map>())
          ChoiceButton(a['label'], key: Key('ans-${q['id']}-${a['value']}'), onPressed: sending ? null : () => _answer(s, q['id'], a['value'])),
        if (offline) _offline(s),
      ]),
    );
  }
}

// ===================================================================== Find a service
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  List<Map<String, dynamic>>? items;
  bool offline = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    s.api.get('/v1/services', q: {'tier': s.tier}).then((r) {
      if (mounted) setState(() => items = ((r as Map)['services'] as List).cast<Map<String, dynamic>>());
    }).catchError((_) {
      if (mounted) setState(() => offline = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: nsBar(title: s.t(['menu', 'row_find']), onBack: () => _home(context), actions: [_exit(context)]),
      body: NsBody(children: [
        if (items == null && !offline) const Center(child: CircularProgressIndicator(color: W.berry)),
        if (offline) _offline(s),
        if (items != null)
          RowGroup(rows: [
            for (final x in items!)
              NsRow(key: Key('svc-${x['id']}'), title: x['name'], subtitle: '${x['area']} · ${x['lga']}',
                  onTap: () => context.push('/service', extra: x)),
          ]),
      ]),
    );
  }
}

class ServiceScreen extends StatefulWidget {
  const ServiceScreen({super.key, required this.svc});
  final Map<String, dynamic> svc;
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  bool busy = false, offline = false;

  Future<void> _getCode(AppState s) async {
    setState(() {
      busy = true;
      offline = false;
    });
    try {
      final r = await s.api.post('/v1/referrals', {'service_id': widget.svc['id'], 'lang': s.lang, 'tier': s.tier}) as Map<String, dynamic>;
      await s.addCode(SavedCode(r['code'], widget.svc['name'], widget.svc['area'], DateTime.now()));
      if (mounted) context.go('/code/${r['code']}');
    } on OfflineException {
      setState(() => offline = true);
    } catch (_) {
      setState(() => offline = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final x = widget.svc;
    String t(String f, String k) => s.t([f, k]);
    return Scaffold(
      appBar: nsBar(title: t('menu', 'row_find'), onBack: () => context.pop(), actions: [_exit(context)]),
      body: NsBody(
        bottom: PrimaryButton(t('app', 'get_code'), key: const Key('get-code'), onPressed: busy ? null : () => _getCode(s)),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: W.shadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ServiceCardTop(free: x['is_free'] == true ? t('referral', 'tag_free') : null,
                  youth: x['youth_friendly'] == true ? t('referral', 'tag_youth') : null, label: t('referral', 'card_image_label')),
              Padding(
                padding: const EdgeInsets.all(12),
                child: DefaultTextStyle(
                  style: const TextStyle(fontSize: 15, height: 20 / 15, color: W.ink),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (x['verified'] != true) ...[
                      Tag(t('extra', 'referral_demo_tag'), bg: const Color(0xFFC2462E), fg: Colors.white),
                      const SizedBox(height: 8),
                    ],
                    Text(x['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(children: [const Icon(Icons.place_outlined, size: 18, color: W.berry), const SizedBox(width: 6),
                      Expanded(child: Text('${x['address']}, ${x['area']}'))]),
                    const SizedBox(height: 6),
                    Row(children: [const Icon(Icons.schedule, size: 18, color: W.berry), const SizedBox(width: 6),
                      Expanded(child: Text('${x['days']}, ${x['hours']}'))]),
                    const SizedBox(height: 10),
                    Text(t('referral', 'expect_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(t('referral', 'expect')),
                  ]),
                ),
              ),
            ]),
          ),
          if (offline) _offline(s),
        ],
      ),
    );
  }
}

// ===================================================================== Referral code
class CodeScreen extends StatelessWidget {
  const CodeScreen({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: nsBar(title: s.t(['app', 'code_title']), onBack: () => _home(context), actions: [_exit(context)]),
      body: NsBody(
        bottom: PrimaryButton(s.t(['app', 'back_home']), key: const Key('back-home'), onPressed: () => _home(context)),
        children: [
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
            child: Column(children: [
              SelectableText(code, key: const Key('referral-code'),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 8, color: W.berry)),
              const SizedBox(height: 12),
              Text(s.t(['app', 'code_how']), textAlign: TextAlign.center, style: bodyText),
            ]),
          ),
        ],
      ),
    );
  }
}

// ===================================================================== Settings
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setPin(BuildContext context, AppState s) async {
    String? first;
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: W.bg,
          title: Text(s.t(['app', first == null ? 'pin_choose' : 'pin_again'])),
          content: SingleChildScrollView(
            child: PinPad(key: ValueKey(first), onComplete: (p) {
              if (first == null) {
                set(() => first = p);
              } else {
                Navigator.pop(ctx, p == first ? p : null);
              }
            }),
          ),
        ),
      ),
    );
    if (pin != null) await s.setPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    String t(String k) => s.t(['app', k]);
    return Scaffold(
      appBar: nsBar(title: t('settings_title'), onBack: () => _home(context), actions: [_exit(context)]),
      body: NsBody(children: [
        RowGroup(rows: [
          NsRow(
            key: const Key('set-lang'),
            title: t('language'),
            trailing: Text(s.lang == 'pcm' ? 'Pidgin' : 'English', style: const TextStyle(color: W.sub)),
            onTap: () => s.setLang(s.lang == 'pcm' ? 'en' : 'pcm'),
          ),
          NsRow(title: t('pin_lock'), trailing: Switch(key: const Key('set-pin'), value: s.hasPin, activeThumbColor: W.berry,
              onChanged: (v) => v ? _setPin(context, s) : s.setPin(null))),
          NsRow(title: t('low_data'), trailing: Switch(value: s.lowData, activeThumbColor: W.berry, onChanged: s.setLowData)),
          NsRow(
            key: const Key('set-delete'),
            title: t('delete'),
            trailing: const SizedBox.shrink(),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  content: Text(t('delete_confirm')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
                    TextButton(key: const Key('delete-confirm'), onPressed: () => Navigator.pop(ctx, true),
                        child: Text(t('delete'), style: const TextStyle(color: W.berry))),
                  ],
                ),
              );
              if (ok == true) {
                await s.deleteEverything();
                if (context.mounted) context.go('/');
              }
            },
          ),
        ]),
        const SizedBox(height: 28),
        Center(
          child: TextButton(key: const Key('staff-link'), onPressed: () => context.go('/staff'),
              child: Text(t('staff_signin'), style: const TextStyle(color: W.sub, fontSize: 13))),
        ),
      ]),
    );
  }
}

// ===================================================================== Crisis
class CrisisScreen extends StatelessWidget {
  const CrisisScreen({super.key});
  static final _num = RegExp(r'\+?\d[\d ]{2,}\d');

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final refs = ((s.pendingCrisis?['refs'] as List?) ?? [['crisis', 'violence']]).cast<List>();
    final callLabel = s.t(['app', 'call_helpline']);
    final number = _num.firstMatch(callLabel)?.group(0);
    return Scaffold(
      appBar: nsBar(title: s.t(['app', 'crisis_title']), onBack: () => context.canPop() ? context.pop() : _home(context), actions: [_exit(context)]),
      body: NsBody(
        bottom: number == null
            ? null
            : PrimaryButton(callLabel, key: const Key('call-helpline'),
                onPressed: () => launchUrl(Uri.parse('tel:${number.replaceAll(' ', '')}'))),
        children: [
          for (final r in refs) ...[
            Panel(border: W.berry, child: Text(s.t(r), style: bodyText)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
