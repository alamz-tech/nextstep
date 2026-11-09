import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/state.dart';
import '../../widgets/chat_ui.dart';

/// Staff screens (facilitators and partner clinics), in the impact-dashboard design style.
/// Reached only by URL (/#/staff), never from the learner chat.
const _bg = Color(0xFFFAF8F4), _line = Color(0xFFE3DFD7), _text2 = Color(0xFF4A5560);

Widget _panel(Widget child) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)),
      child: child,
    );

Scaffold _page(BuildContext context, String title, List<Widget> children, {Widget? fab}) {
  final s = context.read<AppState>();
  return Scaffold(
    backgroundColor: _bg,
    floatingActionButton: fab,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: const Border(bottom: BorderSide(color: _line)),
      title: Row(children: [
        SizedBox(width: 36, height: 36, child: CustomPaint(painter: StepsMark(stroke: Colors.white, dot: W.yellow, tile: W.teal))),
        const SizedBox(width: 10),
        Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
      ]),
      actions: [
        if (s.staff != null)
          TextButton(onPressed: () {
            s.signOutStaff();
            context.go('/staff');
          }, child: Text('Sign out ${s.staff!.username}')),
      ],
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    ),
  );
}

final _primary = FilledButton.styleFrom(backgroundColor: W.teal, minimumSize: const Size(48, 48), shape: const StadiumBorder());

class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key});
  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final u = TextEditingController(), p = TextEditingController();
  String? err;

  Future<void> _login(AppState s) async {
    setState(() => err = null);
    try {
      final r = await s.api.post('/v1/auth/login', {'username': u.text.trim(), 'password': p.text}) as Map<String, dynamic>;
      if (!{'facilitator', 'clinic_partner'}.contains(r['role'])) {
        setState(() => err = 'Admins use the dashboard at /dashboard.');
        return;
      }
      s.api.staffToken = r['token'];
      s.staff = Staff(r['role'], r['username'], (r['org'] as Map?)?['name']);
      if (mounted) context.go(r['role'] == 'clinic_partner' ? '/clinic' : '/staff/sessions');
    } on ApiException catch (e) {
      setState(() => err = e.message);
    } on OfflineException {
      setState(() => err = 'No connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return _page(context, 'Staff sign-in', [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(key: const Key('staff-user'), controller: u, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 10),
          TextField(key: const Key('staff-pass'), controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _login(s)),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Color(0xFFC2462E)))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('staff-login'), style: _primary, onPressed: () => _login(s), child: const Text('Sign in')),
        ])),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ facilitator
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List sessions = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/v1/sessions', staff: true) as Map<String, dynamic>;
      setState(() => sessions = r['sessions']);
    } catch (_) {}
  }

  Future<void> _create(AppState s) async {
    String setting = 'school', band = '15_17';
    final size = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New session'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField(value: setting, decoration: const InputDecoration(labelText: 'Setting'), items: const [
              DropdownMenuItem(value: 'school', child: Text('School')),
              DropdownMenuItem(value: 'community', child: Text('Community')),
              DropdownMenuItem(value: 'clinic', child: Text('Clinic')),
            ], onChanged: (v) => set(() => setting = v!)),
            DropdownButtonFormField(value: band, decoration: const InputDecoration(labelText: 'Audience age'), items: const [
              DropdownMenuItem(value: '15_17', child: Text('15–17')),
              DropdownMenuItem(value: '18_24', child: Text('18–24')),
            ], onChanged: (v) => set(() => band = v!)),
            TextField(controller: size, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Approximate audience size')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(key: const Key('create-session'), style: _primary, onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await s.api.post('/v1/sessions', {'setting': setting, 'session_date': DateTime.now().toIso8601String().substring(0, 10),
        'age_band': band, 'audience_size': int.tryParse(size.text) ?? 30, 'lang': s.lang}, true) as Map<String, dynamic>;
      if (mounted) context.push('/staff/session/${r['id']}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return _page(context, 'Sessions', [
      for (final x in sessions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _panel(ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${x['setting']} · ${x['session_date']} · ${x['age_band'].toString().replaceAll('_', '–')}'),
            subtitle: Text('${x['submitted']} questions · ${x['status']}'),
            trailing: Text(x['join_code'], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
            onTap: () => context.push('/staff/session/${x['id']}'),
          )),
        ),
    ], fab: FloatingActionButton.extended(key: const Key('new-session'), backgroundColor: W.teal, foregroundColor: Colors.white,
        onPressed: () => _create(s), icon: const Icon(Icons.add), label: const Text('New session')));
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.id});
  final String id;
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Map<String, dynamic>? data;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/v1/sessions/${widget.id}/themes', staff: true) as Map<String, dynamic>;
      if (mounted) setState(() => data = r);
    } catch (_) {}
  }

  Future<void> _download(AppState s, String fmt) async {
    final r = await s.api.post('/v1/sessions/${widget.id}/report-link?format=$fmt', {}, true) as Map<String, dynamic>;
    await launchUrl(Uri.parse(s.api.absolute(r['url'])), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    if (data == null) return _page(context, 'Session', [const Center(child: CircularProgressIndicator())]);
    final ses = data!['session'] as Map<String, dynamic>;
    final themes = (data!['themes'] as List).cast<Map<String, dynamic>>();
    final checklist = (ses['checklist'] as Map?)?.cast<String, dynamic>() ?? {};
    return _page(context, 'Session ${ses['join_code']}', [
      Wrap(spacing: 16, runSpacing: 16, children: [
        _panel(Column(children: [
          QrImageView(data: ses['join_url'], size: 200, backgroundColor: Colors.white),
          Text(ses['join_code'], key: const Key('join-code'),
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: W.teal)),
          SelectableText(ses['join_url'], style: const TextStyle(fontSize: 12, color: _text2)),
        ])),
        SizedBox(
          width: 380,
          child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Joined ${ses['joins']} · Questions ${ses['submitted']} · Filtered ${ses['filtered']}'),
            if ((data!['flagged_count'] ?? 0) > 0)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: W.blue, width: 2)),
                child: Text('${data!['flagged_count']} flagged for support. ${data!['support_reminder']}', key: const Key('flag-reminder')),
              ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => context.push('/staff/projector/${widget.id}'), child: const Text('Projector')),
              OutlinedButton(onPressed: () => _download(s, 'csv'), child: const Text('Report CSV')),
              OutlinedButton(onPressed: () => _download(s, 'pdf'), child: const Text('Report PDF')),
              if (ses['status'] == 'open')
                TextButton(onPressed: () async {
                  await s.api.post('/v1/sessions/${widget.id}/close', {}, true);
                  _load();
                }, child: const Text('Close session')),
            ]),
          ])),
        ),
      ]),
      if (ses['setting'] == 'school') ...[
        const SizedBox(height: 16),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Before a school session (reminder only, not legal advice)', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final (k, label) in [('school_permission', 'School permission obtained'), ('consent_requirements', 'Consent requirements met')])
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checklist[k] == true,
              title: Text(label),
              onChanged: (v) async {
                checklist[k] = v == true;
                await s.api.post('/v1/sessions/${widget.id}/checklist', {'items': checklist}, true);
                _load();
              },
            ),
        ])),
      ],
      const SizedBox(height: 16),
      for (final t in themes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${t['label']} · ${t['count']}', style: const TextStyle(fontWeight: FontWeight.w700, color: W.teal))),
              Checkbox(
                value: t['answered'] == true,
                onChanged: (v) async {
                  await s.api.post('/v1/sessions/${widget.id}/themes/answered', {'key': t['key'], 'answered': v == true}, true);
                  _load();
                },
              ),
            ]),
            if (t['suggested'] != null) ...[
              Text(t['suggested']['text']),
              const SizedBox(height: 6),
              Text('Source: ${(t['suggested']['sources'] as List).first['source_document']}', style: const TextStyle(fontSize: 12, color: _text2)),
            ],
          ])),
        ),
    ]);
  }
}

/// Large-type view for a projector: themes and grounded answers only, never raw questions.
class ProjectorScreen extends StatefulWidget {
  const ProjectorScreen({super.key, required this.id});
  final String id;
  @override
  State<ProjectorScreen> createState() => _ProjectorScreenState();
}

class _ProjectorScreenState extends State<ProjectorScreen> {
  Map<String, dynamic>? data;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.get('/v1/sessions/${widget.id}/projector', staff: true);
      if (mounted) setState(() => data = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final themes = ((data?['themes'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Scaffold(
      backgroundColor: _bg,
      body: ListView(padding: const EdgeInsets.all(32), children: [
        Text('Code ${data?['join_code'] ?? ''}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: W.teal)),
        const SizedBox(height: 20),
        for (final t in themes)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['label'], style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: W.teal)),
              const SizedBox(height: 10),
              if (t['answer'] != null) Text(t['answer'], style: const TextStyle(fontSize: 24, height: 1.4)),
            ])),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ clinic partner
class ClinicScreen extends StatefulWidget {
  const ClinicScreen({super.key});
  @override
  State<ClinicScreen> createState() => _ClinicScreenState();
}

class _ClinicScreenState extends State<ClinicScreen> {
  final code = TextEditingController();
  String? status;

  Future<void> _confirm(AppState s) async {
    try {
      final r = await s.api.post('/v1/clinic/confirm', {'code': code.text.trim().toUpperCase()}, true) as Map<String, dynamic>;
      setState(() => status = r['status']);
      if (r['status'] == 'confirmed') code.clear();
    } catch (_) {
      setState(() => status = 'offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    const msg = {
      'confirmed': 'Visit confirmed.',
      'already_confirmed': 'Already confirmed.',
      'not_found': 'Code not found.',
      'expired': 'Code expired.',
      'offline': 'No connection.',
    };
    return _page(context, 'Confirm a referral', [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const Key('clinic-code'),
            controller: code,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 30, letterSpacing: 6, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Referral code', counterText: ''),
            onSubmitted: (_) => _confirm(s),
          ),
          const SizedBox(height: 12),
          FilledButton(key: const Key('clinic-confirm'), style: _primary, onPressed: () => _confirm(s), child: const Text('Confirm visit')),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(msg[status] ?? status!, key: const Key('clinic-status'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: status == 'confirmed' ? const Color(0xFF2E7D4F) : const Color(0xFFC2462E))),
            ),
        ])),
      ),
    ]);
  }
}
