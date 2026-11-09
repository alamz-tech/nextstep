import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Staff screens are in English for the prototype (facilitators, clinic staff and admins).
class StaffLoginScreen extends StatefulWidget {
  const StaffLoginScreen({super.key, this.next});
  final String? next;
  @override
  State<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends State<StaffLoginScreen> {
  final u = TextEditingController(), p = TextEditingController();
  String? err;
  bool busy = false;

  Future<void> _login(AppState s) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final r = await s.api.post('/v1/auth/login', {'username': u.text.trim(), 'password': p.text}) as Map<String, dynamic>;
      s.api.staffToken = r['token'];
      s.staff = Staff(r['role'], r['username'], (r['org'] as Map?)?['name']);
      s.notifyListeners();
      if (!mounted) return;
      context.go(switch (r['role']) { 'clinic_partner' => '/clinic', 'facilitator' => '/staff/sessions', _ => '/staff/admin' });
    } on ApiException catch (e) {
      setState(() => err = e.message);
    } on OfflineException {
      setState(() => err = 'No connection.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Staff sign-in')),
      body: SafeArea(
        child: NsPage(maxWidth: 420, children: [
          const Logo(size: 48),
          const SizedBox(height: 12),
          Text('Facilitators, partner clinics and admins', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Accounts are created by your organisation admin.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(key: const Key('staff-user'), controller: u, decoration: const InputDecoration(labelText: 'Username'), autofillHints: const [AutofillHints.username]),
          const SizedBox(height: 10),
          TextField(key: const Key('staff-pass'), controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _login(s), autofillHints: const [AutofillHints.password]),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: NsColors.of(context).accent))),
          const SizedBox(height: 16),
          FilledButton(key: const Key('staff-login'), onPressed: busy ? null : () => _login(s), child: const Text('Sign in')),
        ]),
      ),
    );
  }
}

AppBar staffBar(BuildContext context, String title, {List<Widget> actions = const []}) {
  final s = context.read<AppState>();
  return AppBar(title: Text(title), actions: [
    ...actions,
    if (s.staff != null)
      TextButton.icon(
        onPressed: () {
          s.signOutStaff();
          context.go('/');
        },
        icon: const Icon(Icons.logout),
        label: Text(s.staff!.username),
      ),
  ]);
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
    final s = context.read<AppState>();
    try {
      final r = await s.api.get('/v1/sessions', staff: true) as Map<String, dynamic>;
      setState(() => sessions = r['sessions']);
    } catch (_) {}
  }

  Future<void> _create(AppState s) async {
    String setting = 'school', band = '15_17', lang = 'en';
    DateTime date = DateTime.now();
    final size = TextEditingController(text: '30');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New session'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField(value: setting, decoration: const InputDecoration(labelText: 'Setting'),
                  items: const [DropdownMenuItem(value: 'school', child: Text('School')), DropdownMenuItem(value: 'community', child: Text('Community')),
                    DropdownMenuItem(value: 'clinic', child: Text('Clinic'))], onChanged: (v) => set(() => setting = v!)),
              const SizedBox(height: 10),
              DropdownButtonFormField(value: band, decoration: const InputDecoration(labelText: 'Audience age band'),
                  items: const [DropdownMenuItem(value: '15_17', child: Text('15–17')), DropdownMenuItem(value: '18_24', child: Text('18–24'))],
                  onChanged: (v) => set(() => band = v!)),
              const Padding(padding: EdgeInsets.only(top: 4), child: Text('Younger audiences are out of scope for this prototype.', style: TextStyle(fontSize: 12))),
              const SizedBox(height: 10),
              DropdownButtonFormField(value: lang, decoration: const InputDecoration(labelText: 'Language for students'),
                  items: const [DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'pcm', child: Text('Pidgin'))],
                  onChanged: (v) => set(() => lang = v!)),
              const SizedBox(height: 10),
              TextField(controller: size, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Approximate audience size')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Date: ${date.toIso8601String().substring(0, 10)}'),
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2026), lastDate: DateTime(2030));
                  if (d != null) set(() => date = d);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(key: const Key('create-session'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await s.api.post('/v1/sessions', {'setting': setting, 'session_date': date.toIso8601String().substring(0, 10), 'age_band': band,
        'audience_size': int.tryParse(size.text) ?? 30, 'lang': lang}, true) as Map<String, dynamic>;
      if (mounted) context.push('/staff/session/${r['id']}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: staffBar(context, 'Sessions', actions: [
        IconButton(tooltip: 'Session kits', onPressed: () => context.push('/staff/kits'), icon: const Icon(Icons.menu_book_outlined)),
      ]),
      floatingActionButton: FloatingActionButton.extended(key: const Key('new-session'), onPressed: () => _create(s), icon: const Icon(Icons.add), label: const Text('New session')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: NsPage(children: [
          if (s.staff?.orgName != null) Text(s.staff!.orgName!, style: Theme.of(context).textTheme.bodySmall),
          if (sessions.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No sessions yet. Create one to get a QR code and join code.')),
          for (final x in sessions)
            Card(
              child: ListTile(
                title: Text('${x['setting']} · ${x['session_date']}'),
                subtitle: Text('Age ${x['age_band'].toString().replaceAll('_', '–')} · about ${x['audience_size']} people · ${x['submitted']} questions · ${x['status']}'),
                trailing: Text(x['join_code'], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2)),
                onTap: () => context.push('/staff/session/${x['id']}'),
              ),
            ),
        ]),
      ),
    );
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
  static const checklistLabels = {
    'school_permission': 'School permission obtained',
    'consent_requirements': 'Consent requirements met (e.g. parent/guardian where required)',
    'safeguarding_contact': 'Safeguarding contact identified for this session',
    'support_contacts_ready': 'Verified support contacts ready to share with the group',
  };

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
    final s = context.read<AppState>();
    try {
      final r = await s.api.get('/v1/sessions/${widget.id}/themes', staff: true) as Map<String, dynamic>;
      if (mounted) setState(() => data = r);
    } catch (_) {}
  }

  Future<void> _download(AppState s, String fmt) async {
    try {
      final r = await s.api.post('/v1/sessions/${widget.id}/report-link?format=$fmt', {}, true) as Map<String, dynamic>;
      await launchUrl(Uri.parse(s.api.absolute(r['url'])), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final tt = Theme.of(context).textTheme;
    if (data == null) return Scaffold(appBar: staffBar(context, 'Session'), body: const Center(child: CircularProgressIndicator()));
    final ses = data!['session'] as Map<String, dynamic>;
    final themes = (data!['themes'] as List).cast<Map<String, dynamic>>();
    final checklist = (ses['checklist'] as Map?)?.cast<String, dynamic>() ?? {};
    final open = ses['status'] == 'open';
    return Scaffold(
      appBar: staffBar(context, 'Session ${ses['join_code']}', actions: [
        IconButton(tooltip: 'Projector view', onPressed: () => context.push('/staff/projector/${widget.id}'), icon: const Icon(Icons.cast)),
      ]),
      body: NsPage(maxWidth: 900, children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Container(color: Colors.white, padding: const EdgeInsets.all(8),
                    child: QrImageView(data: ses['join_url'], size: 200, backgroundColor: Colors.white)),
                const SizedBox(height: 8),
                Text(ses['join_code'], key: const Key('join-code'),
                    style: TextStyle(fontFamily: kDisplay, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: c.primary)),
                SelectableText(ses['join_url'], style: tt.bodySmall),
                const SizedBox(height: 4),
                Text('Students scan, no install or login.', style: tt.bodySmall),
              ]),
            ),
          ),
          SizedBox(
            width: 380,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ses['setting']} · ${ses['session_date']} · age ${ses['age_band'].toString().replaceAll('_', '–')}', style: tt.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _stat(context, 'Joined', ses['joins']),
                    _stat(context, 'Questions', ses['submitted']),
                    _stat(context, 'Filtered', ses['filtered']),
                    _stat(context, 'Referral codes', ses['referral_cards']),
                  ]),
                  const SizedBox(height: 12),
                  if ((data!['flagged_count'] ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.supportTint, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.support, width: 2)),
                      child: Text('${data!['flagged_count']} question(s) flagged for support. ${data!['support_reminder']}', key: const Key('flag-reminder')),
                    ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(onPressed: () => _download(s, 'csv'), icon: const Icon(Icons.table_view), label: const Text('Report CSV')),
                    OutlinedButton.icon(onPressed: () => _download(s, 'pdf'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Report PDF')),
                    if (open)
                      TextButton(
                        onPressed: () async {
                          await s.api.post('/v1/sessions/${widget.id}/close', {}, true);
                          _load();
                        },
                        child: const Text('Close session (deletes question text)'),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
        if (ses['setting'] == 'school') ...[
          const SizedBox(height: 16),
          Text('Before a school session', style: tt.titleLarge),
          Text('A reminder checklist only. This is not legal advice.', style: tt.bodySmall),
          for (final e in checklistLabels.entries)
            CheckboxListTile(
              value: checklist[e.key] == true,
              title: Text(e.value),
              onChanged: (v) async {
                checklist[e.key] = v == true;
                await s.api.post('/v1/sessions/${widget.id}/checklist', {'items': checklist}, true);
                _load();
              },
            ),
        ],
        const SizedBox(height: 16),
        Text('Question themes', style: tt.titleLarge),
        Text('Grouped automatically. Raw questions are never shown. Suggested answers come only from the reviewed knowledge base.', style: tt.bodySmall),
        const SizedBox(height: 8),
        if (themes.isEmpty) const Text('No questions yet.'),
        for (final t in themes) _theme(context, s, t),
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, dynamic v) {
    final c = NsColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$v', style: const TextStyle(fontFamily: kDisplay, fontSize: 24, fontWeight: FontWeight.w700)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _theme(BuildContext context, AppState s, Map<String, dynamic> t) {
    final sug = t['suggested'] as Map<String, dynamic>?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          shape: const Border(),
          title: Text(t['label']),
          subtitle: Text('${t['count']} question(s)${t['answered'] == true ? ' · answered' : ''}'),
          leading: Icon(t['answered'] == true ? Icons.check_circle : Icons.help_outline, color: NsColors.of(context).primary),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sug != null) ...[
              Text(sug['text']),
              SourcesLine(sources: sug['sources'] ?? []),
              if (sug['draft'] == true) const DraftChip(),
            ] else
              const Text('No reviewed answer in the knowledge base yet. Answer from your training, or refer students to a service.'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () async {
                await s.api.post('/v1/sessions/${widget.id}/themes/answered', {'key': t['key'], 'answered': t['answered'] != true}, true);
                _load();
              },
              child: Text(t['answered'] == true ? 'Mark not answered' : 'Mark answered'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large-type view for a projector: themes and grounded answers, never raw questions.
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
    final c = NsColors.light;
    final themes = ((data?['themes'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Theme(
      data: buildTheme(Brightness.light),
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: Text('Join with code ${data?['join_code'] ?? ''}')),
        body: ListView(padding: const EdgeInsets.all(32), children: [
          const Text('Your questions, answered', style: TextStyle(fontFamily: kDisplay, fontSize: 44, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          for (final t in themes)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.line, width: 2)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${t['label']}  ·  ${t['count']}', style: TextStyle(fontFamily: kDisplay, fontSize: 32, fontWeight: FontWeight.w700, color: c.primary)),
                  const SizedBox(height: 12),
                  Text(t['answer'] ?? 'Your facilitator will answer this one.', style: const TextStyle(fontSize: 26, height: 1.4)),
                  if ((t['sources'] as List?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Source: ${(t['sources'] as List).first['source_document']}', style: TextStyle(fontSize: 16, color: c.text2)),
                    ),
                ]),
              ),
            ),
          Text('General information, not medical advice. Draft content pending clinician review.', style: TextStyle(fontSize: 18, color: c.text2)),
        ]),
      ),
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
  bool busy = false;

  Future<void> _confirm(AppState s) async {
    setState(() => busy = true);
    try {
      final r = await s.api.post('/v1/clinic/confirm', {'code': code.text.trim().toUpperCase()}, true) as Map<String, dynamic>;
      setState(() => status = r['status']);
      if (r['status'] == 'confirmed') code.clear();
    } on ApiException catch (e) {
      setState(() => status = e.message);
    } on OfflineException {
      setState(() => status = 'offline');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = NsColors.of(context);
    final msg = {
      'confirmed': ('Visit confirmed. Thank you.', c.success),
      'already_confirmed': ('This code was already confirmed.', c.text2),
      'not_found': ('Code not found. Check the letters and try again.', c.accent),
      'expired': ('This code has expired.', c.accent),
      'offline': ('No connection.', c.accent),
    }[status];
    return Scaffold(
      appBar: staffBar(context, 'Confirm a referral'),
      body: NsPage(maxWidth: 480, children: [
        Text(s.staff?.orgName ?? '', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Enter the code the young person shows you.', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('No names or clinical details are needed or stored.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        TextField(
          key: const Key('clinic-code'),
          controller: code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 8,
          style: const TextStyle(fontFamily: kDisplay, fontSize: 32, letterSpacing: 6, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(hintText: 'ABC123', counterText: ''),
          onSubmitted: (_) => _confirm(s),
        ),
        const SizedBox(height: 12),
        FilledButton(key: const Key('clinic-confirm'), onPressed: busy ? null : () => _confirm(s), child: const Text('Confirm visit')),
        const SizedBox(height: 16),
        if (msg != null) Text(msg.$1, key: const Key('clinic-status'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: msg.$2))
        else if (status != null) Text(status!),
      ]),
    );
  }
}

// ------------------------------------------------------------------ admin
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List users = [], orgs = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    try {
      final u = await s.api.get('/v1/admin/users', staff: true) as Map<String, dynamic>;
      final o = await s.api.get('/v1/admin/orgs', staff: true) as Map<String, dynamic>;
      setState(() {
        users = u['users'];
        orgs = o['orgs'];
      });
    } catch (_) {}
  }

  Future<void> _addUser(AppState s) async {
    final u = TextEditingController(), p = TextEditingController();
    String role = 'facilitator';
    String? org = orgs.isNotEmpty ? orgs.first['id'] : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New account'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: u, decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 8),
            TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password (10+ chars)')),
            const SizedBox(height: 8),
            DropdownButtonFormField(value: role, items: const [
              DropdownMenuItem(value: 'facilitator', child: Text('Facilitator')),
              DropdownMenuItem(value: 'clinic_partner', child: Text('Clinic partner')),
              DropdownMenuItem(value: 'org_admin', child: Text('Org admin')),
            ], onChanged: (v) => set(() => role = v!)),
            if (s.staff?.role == 'platform_admin' && orgs.isNotEmpty)
              DropdownButtonFormField<String>(value: org, items: [for (final o in orgs) DropdownMenuItem(value: o['id'], child: Text(o['name']))],
                  onChanged: (v) => set(() => org = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await s.api.post('/v1/admin/users', {'username': u.text.trim(), 'password': p.text, 'role': role, 'org_id': org}, true);
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: staffBar(context, 'Organisation admin'),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addUser(s), icon: const Icon(Icons.person_add), label: const Text('Add account')),
      body: NsPage(children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.insights),
            title: const Text('Impact dashboard'),
            subtitle: const Text('Aggregate counts only'),
            onTap: () => launchUrl(Uri.parse(s.api.absolute('/dashboard'))),
          ),
        ),
        const SizedBox(height: 12),
        Text('Accounts', style: Theme.of(context).textTheme.titleLarge),
        for (final u in users)
          ListTile(title: Text(u['username']), subtitle: Text(u['role']), trailing: u['active'] == 1 ? null : const Text('disabled')),
      ]),
    );
  }
}
