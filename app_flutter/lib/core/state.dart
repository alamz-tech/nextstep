import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

/// A referral code the learner got, kept only on this device (encrypted storage).
class SavedCode {
  SavedCode(this.code, this.serviceName, this.area, this.created, {this.reminders = false, this.outcome});
  final String code, serviceName, area;
  final DateTime created;
  bool reminders;
  String? outcome; // went | not_yet | need_help
  bool get active => DateTime.now().difference(created).inDays < 90;
  int get notifyBase => (code.hashCode & 0x3fffffff) * 2; // two ids per code: day 3, day 7
  Map<String, dynamic> toJson() => {'code': code, 'name': serviceName, 'area': area, 'created': created.toIso8601String(),
        'reminders': reminders, 'outcome': outcome};
  static SavedCode fromJson(Map j) => SavedCode(j['code'], j['name'] ?? '', j['area'] ?? '', DateTime.parse(j['created']),
      reminders: j['reminders'] == true, outcome: j['outcome']);
}

/// App state. The chat lives in memory only: nothing the learner types is kept
/// on the device, and the server keeps no message text.
class AppState extends ChangeNotifier {
  final store = Store();
  final copy = Copy();
  late Api api;

  bool ready = false;
  bool setupDone = false;
  String tier = '';
  String lang = 'en';
  bool lowData = false;
  String? _pinHash, _pinSalt;
  bool locked = false; // PIN screen showing
  bool disguised = false; // quick exit calculator showing
  bool busy = false;
  bool offline = false;
  bool demoMode = false;
  List<Msg> msgs = [];
  List<SavedCode> codes = [];
  Map<String, dynamic>? pendingCrisis; // set when the safety layer fires; the crisis screen shows it
  Staff? staff;

  bool get hasPin => _pinHash != null;
  SavedCode? get activeCode => codes.where((c) => c.active).firstOrNull;
  String t(List ref, [Map? p]) => copy.t(ref, lang, p);

  Future<void> init() async {
    await copy.load();
    await _loadLocal();
    ready = true;
    notifyListeners();
    try {
      copy.overlay((await api.get('/v1/chat/copy')) as Map<String, dynamic>);
      demoMode = ((await api.get('/v1/config')) as Map)['demo_mode'] == true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadLocal() async {
    var id = await store.read('install_id');
    if (id == null) {
      id = const Uuid().v4();
      await store.write('install_id', id);
    }
    api = Api(id);
    final p = await store.readJson('prefs') ?? {};
    setupDone = p['setupDone'] == true;
    tier = p['tier'] ?? '';
    lang = p['lang'] ?? 'en';
    lowData = p['lowData'] == true;
    _pinHash = p['pinHash'];
    _pinSalt = p['pinSalt'];
    locked = setupDone && _pinHash != null;
    final c = await store.read('codes');
    codes = c == null ? [] : (jsonDecode(c) as List).map((e) => SavedCode.fromJson(e)).toList();
  }

  Future<void> _savePrefs() => store.writeJson('prefs', {
        'setupDone': setupDone, 'tier': tier, 'lang': lang, 'lowData': lowData, 'pinHash': _pinHash, 'pinSalt': _pinSalt,
      });

  // ---------------------------------------------------------------- first-time setup
  /// Under 15: count it (aggregate only) and keep nothing on the device.
  Future<void> under15() async {
    try {
      await api.post('/v1/learner/onboard', {'lang': lang, 'age_tier': 'under_15'});
    } catch (_) {}
  }

  Future<void> finishSetup(String ageTier, String language) async {
    tier = ageTier;
    lang = language;
    setupDone = true;
    await _savePrefs();
    try {
      await api.post('/v1/learner/onboard', {'lang': lang, 'age_tier': tier});
    } catch (_) {}
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings
  Future<void> setLang(String l) async {
    lang = l;
    await _savePrefs();
    notifyListeners();
  }

  Future<void> setLowData(bool v) async {
    lowData = v;
    await _savePrefs();
    notifyListeners();
  }

  String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String? pin) async {
    if (pin == null) {
      _pinHash = _pinSalt = null;
    } else {
      final r = Random.secure();
      _pinSalt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
      _pinHash = _hash(pin, _pinSalt!);
    }
    await _savePrefs();
    notifyListeners();
  }

  bool unlockWithPin(String pin) {
    if (_pinHash == null || _hash(pin, _pinSalt!) != _pinHash) return false;
    locked = false;
    disguised = false;
    notifyListeners();
    return true;
  }

  void lockIfPin() {
    if (setupDone && hasPin && !locked) {
      locked = true;
      notifyListeners();
    }
  }

  /// Delete my data: server first (referral codes, chat state), then wipe the device.
  Future<bool> deleteEverything() async {
    var ok = true;
    try {
      await api.delete('/v1/learner/data');
    } catch (_) {
      ok = false;
    }
    try {
      await api.post('/v1/chat', {'kind': 'text', 'text': 'DELETE'});
    } catch (_) {}
    await Notifications.cancelAll();
    await store.wipe();
    msgs = [];
    await _loadLocal();
    notifyListeners();
    return ok;
  }

  // ---------------------------------------------------------------- referral codes
  Future<void> addCode(SavedCode c) async {
    codes.insert(0, c);
    await _saveCodes();
    notifyListeners();
  }

  Future<void> _saveCodes() => store.write('codes', jsonEncode(codes.map((e) => e.toJson()).toList()));

  SavedCode? codeFor(String code) => codes.where((c) => c.code == code).firstOrNull;

  /// Day-3 and day-7 check-ins, scheduled on the device only (Android). Neutral text.
  Future<void> setReminders(SavedCode c, bool on) async {
    c.reminders = on;
    if (on) {
      await Notifications.scheduleCheckIns(t(['followup', 'ping']), t(['followup', 'ask']), baseId: c.notifyBase);
      try {
        await api.post('/v1/learner/events', {'event': 'reminder_opt_in', 'lang': lang, 'tier': tier});
      } catch (_) {}
    } else {
      await Notifications.cancel(c.notifyBase);
    }
    await _saveCodes();
    notifyListeners();
  }

  /// "Went / not yet / need help": aggregate count only. Returns a crisis payload if the barrier needs one.
  Future<Map<String, dynamic>?> recordOutcome(SavedCode c, String outcome, {String barrier = ''}) async {
    c.outcome = outcome;
    if (outcome == 'went' && c.reminders) await setReminders(c, false);
    await _saveCodes();
    notifyListeners();
    try {
      final r = await api.post('/v1/learner/outcome', {'outcome': outcome, 'barrier': barrier, 'lang': lang, 'tier': tier}) as Map<String, dynamic>;
      return r['crisis'] as Map<String, dynamic>?;
    } catch (_) {
      return barrier == 'blocked' ? {'refs': [['crisis', 'violence']]} : null;
    }
  }

  // ---------------------------------------------------------------- quick exit
  void quickExit() {
    msgs = [];
    disguised = true;
    locked = hasPin;
    notifyListeners();
  }

  /// From the calculator: without a PIN, a long-press on "=" returns.
  void unlockNoPin() {
    if (hasPin) return;
    disguised = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- Ask (chat)
  Future<void> startAsk() async {
    msgs = [];
    busy = true;
    offline = false;
    notifyListeners();
    try {
      await _apply(await api.post('/v1/chat/start', {'lang': lang, 'tier': tier}) as Map<String, dynamic>);
    } catch (_) {
      offline = true;
    } finally {
      busy = false;
      notifyListeners();
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

  Future<void> _apply(Map<String, dynamic> r) async {
    final crisisRefs = <List>[];
    for (final m in (r['messages'] as List).cast<Map<String, dynamic>>()) {
      msgs.add(Msg(m, from: m['kind'] == 'system' ? 'sys' : 'bot'));
      final ref = m['ref'] as List?;
      if (ref != null && ref[0] == 'crisis' && ['violence', 'selfharm', 'pep'].contains(ref[1])) crisisRefs.add(ref);
    }
    if (crisisRefs.isNotEmpty) pendingCrisis = {'refs': crisisRefs};
    for (final a in (r['actions'] as List).cast<Map<String, dynamic>>()) {
      switch (a['type']) {
        case 'schedule_followups':
        case 'ensure_followup':
          await Notifications.scheduleCheckIns(t(['followup', 'ping']), t(['followup', 'ask']));
        case 'cancel_followups':
          await Notifications.cancelAll();
        case 'delete_user':
          // STOP / DELETE typed in the chat: wipe the device too.
          await Notifications.cancelAll();
          await store.wipe();
          await _loadLocal();
      }
    }
  }

  void signOutStaff() {
    staff = null;
    api.staffToken = null;
    notifyListeners();
  }
}
