import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'copy.dart';
import 'notifications.dart';
import 'store.dart';

class Staff {
  Staff(this.role, this.username, this.orgName);
  final String role, username;
  final String? orgName;
}

/// One chat message, exactly as the engine sends it (copy refs, buttons, list, card).
class Msg {
  Msg(this.data, {this.from = 'bot'});
  final Map<String, dynamic> data;
  final String from; // bot | user | sys
}

/// App state. The chat lives in memory only: nothing the learner types is kept
/// on the device, and the server keeps no message text.
class AppState extends ChangeNotifier {
  final store = Store();
  final copy = Copy();
  late Api api;

  bool ready = false;
  bool disguised = false; // quick exit
  bool busy = false;
  bool offline = false;
  bool demoMode = false;
  String lang = 'en';
  List<Msg> msgs = [];
  Staff? staff;

  String t(List ref, [Map? p]) => copy.t(ref, lang, p);

  Future<void> init() async {
    await copy.load();
    var id = await store.read('install_id');
    if (id == null) {
      id = const Uuid().v4();
      await store.write('install_id', id);
    }
    api = Api(id);
    lang = await store.read('lang') ?? 'en';
    ready = true;
    notifyListeners();
    try {
      copy.overlay((await api.get('/v1/chat/copy')) as Map<String, dynamic>);
      demoMode = ((await api.get('/v1/config')) as Map)['demo_mode'] == true;
      notifyListeners();
    } catch (_) {}
  }

  /// Opening the app: say Hi (or deliver a due check-in).
  Future<void> start() async {
    if (msgs.isNotEmpty) return;
    final due = int.tryParse(await store.read('followup_due') ?? '');
    if (due != null && DateTime.now().millisecondsSinceEpoch >= due) {
      await store.write('followup_due', null);
      await send({'kind': 'followup_due'});
    } else {
      await send({'kind': 'text', 'text': 'Hi'}, echo: false);
    }
  }

  Future<void> sendText(String text) => send({'kind': 'text', 'text': text}, user: {'texts': {'en': text}});

  Future<void> tapButton(String id, List ref) => send({'kind': 'button', 'button': id}, user: {'ref': ref});

  Future<void> send(Map<String, dynamic> body, {Map<String, dynamic>? user, bool echo = true}) async {
    if (busy) return;
    if (echo && user != null) msgs.add(Msg(user, from: 'user'));
    busy = true;
    offline = false;
    notifyListeners();
    try {
      await _apply(await api.post('/v1/chat', body) as Map<String, dynamic>);
    } on OfflineException {
      offline = true;
    } catch (_) {
      offline = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> sendVoice(List<int> bytes, String name) async {
    final placeholder = Msg({'voice': true, 'texts': {'en': ''}}, from: 'user');
    msgs.add(placeholder);
    busy = true;
    notifyListeners();
    try {
      final r = await api.postAudio('/v1/chat/voice', bytes, name, {}) as Map<String, dynamic>;
      placeholder.data['texts'] = {'en': r['transcript'] ?? ''};
      await _apply(r);
    } catch (_) {
      offline = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Demo builds: the design's sample voice note.
  Future<void> sendDemoVoice() async {
    if (busy) return;
    msgs.add(Msg({'voice': true, 'ref': ['qa', 'user_voice']}, from: 'user'));
    busy = true;
    notifyListeners();
    try {
      await _apply(await api.post('/v1/chat/demo-voice') as Map<String, dynamic>);
    } catch (_) {
      offline = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _apply(Map<String, dynamic> r) async {
    for (final m in (r['messages'] as List).cast<Map<String, dynamic>>()) {
      msgs.add(Msg(m, from: m['kind'] == 'system' ? 'sys' : 'bot'));
    }
    if (r['lang'] is String && r['lang'] != lang) {
      lang = r['lang'];
      await store.write('lang', lang);
    }
    for (final a in (r['actions'] as List).cast<Map<String, dynamic>>()) {
      switch (a['type']) {
        case 'schedule_followups':
        case 'ensure_followup':
          await Notifications.scheduleCheckIns(t(['followup', 'ping']), t(['followup', 'ask']));
          await store.write('followup_due',
              '${DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch}');
        case 'cancel_followups':
          await Notifications.cancelAll();
          await store.write('followup_due', null);
        case 'simulate_followup':
          busy = false;
          await send({'kind': 'followup_due'});
        case 'delete_user':
          // STOP / DELETE: wipe the device too. Only the goodbye message stays on screen.
          await Notifications.cancelAll();
          await store.wipe();
          await store.write('install_id', const Uuid().v4());
          api = Api((await store.read('install_id'))!);
      }
    }
  }

  void quickExit() {
    msgs = [];
    disguised = true;
    notifyListeners();
  }

  void unlock() {
    disguised = false;
    notifyListeners();
    start();
  }

  void signOutStaff() {
    staff = null;
    api.staffToken = null;
    notifyListeners();
  }
}
