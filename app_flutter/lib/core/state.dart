import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'copy.dart';
import 'notifications.dart';
import 'store.dart';

/// One saved referral, kept only on this device (encrypted).
class SavedReferral {
  SavedReferral({required this.code, required this.serviceId, required this.serviceName, required this.area,
      required this.demo, required this.created, this.outcome, this.confirmed = false, this.reminders = false});
  final String code, serviceId, serviceName, area, created;
  final bool demo;
  String? outcome;
  bool confirmed, reminders;

  Map<String, dynamic> toJson() => {'code': code, 'serviceId': serviceId, 'serviceName': serviceName, 'area': area,
        'demo': demo, 'created': created, 'outcome': outcome, 'confirmed': confirmed, 'reminders': reminders};
  static SavedReferral fromJson(Map<String, dynamic> j) => SavedReferral(code: j['code'], serviceId: j['serviceId'],
      serviceName: j['serviceName'], area: j['area'] ?? '', demo: j['demo'] ?? true, created: j['created'] ?? '',
      outcome: j['outcome'], confirmed: j['confirmed'] ?? false, reminders: j['reminders'] ?? false);
}

class Staff {
  Staff(this.role, this.username, this.orgName);
  final String role, username;
  final String? orgName;
}

/// App-wide state. Learner state lives only on the device; the server never
/// receives anything that identifies the person.
class AppState extends ChangeNotifier {
  final store = Store();
  final copy = Copy();
  late Api api;

  bool ready = false;
  bool onboarded = false;
  String lang = 'en';
  String tier = '';
  bool lowData = false;
  bool keepHistory = false;
  bool locked = false; // PIN screen or neutral disguise showing
  bool disguised = false; // quick exit: neutral calculator screen
  String? _pinHash;
  String? _pinSalt;
  Map<String, dynamic>? bundle;
  List<SavedReferral> referrals = [];
  List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? pendingCrisis; // shown by the crisis screen
  Staff? staff;

  bool get hasPin => _pinHash != null;
  String t(String flow, String key, [Map<String, String>? p]) => copy.t(flow, key, lang, p);

  Future<void> init() async {
    await copy.loadAssets();
    var id = await store.read('install_id');
    if (id == null) {
      id = const Uuid().v4();
      await store.write('install_id', id);
    }
    api = Api(id);
    // A previous "delete my data" made offline: finish the server-side delete now.
    final pending = await store.read('pending_server_delete');
    if (pending != null) {
      try {
        await Api(pending).delete('/v1/learner/data');
        await store.write('pending_server_delete', null);
      } catch (_) {}
    }
    final prefs = await store.readJson('prefs') ?? {};
    onboarded = prefs['onboarded'] == true;
    lang = prefs['lang'] ?? 'en';
    tier = prefs['tier'] ?? '';
    lowData = prefs['lowData'] == true;
    keepHistory = prefs['keepHistory'] == true;
    _pinHash = prefs['pinHash'];
    _pinSalt = prefs['pinSalt'];
    locked = _pinHash != null;
    final refs = await store.read('referrals');
    if (refs != null) {
      referrals = (jsonDecode(refs) as List).map((e) => SavedReferral.fromJson(e)).toList();
    }
    if (keepHistory) {
      final h = await store.read('history');
      if (h != null) history = (jsonDecode(h) as List).cast<Map<String, dynamic>>();
    }
    bundle = await store.readJson('bundle');
    copy.overlay(bundle?['copy'] as Map<String, dynamic>?);
    ready = true;
    notifyListeners();
    refreshBundle();
    if (onboarded) {
      api.post('/v1/learner/events', {'event': 'app_open', 'lang': lang, 'tier': tier}).catchError((_) => null);
    }
  }

  Future<void> _savePrefs() => store.writeJson('prefs', {
        'onboarded': onboarded, 'lang': lang, 'tier': tier, 'lowData': lowData, 'keepHistory': keepHistory,
        'pinHash': _pinHash, 'pinSalt': _pinSalt,
      });

  Future<void> refreshBundle() async {
    try {
      final b = await api.get('/v1/content/bundle',
          extra: bundle?['version'] != null ? {'If-None-Match': '"${bundle!['version']}"'} : null);
      if (b is Map<String, dynamic>) {
        bundle = b;
        copy.overlay(b['copy'] as Map<String, dynamic>?);
        await store.writeJson('bundle', b);
        notifyListeners();
      }
    } catch (_) {/* offline: keep cached bundle */}
  }

  // ---------------------------------------------------------------- onboarding
  Future<bool> completeOnboarding(String ageTier, String language) async {
    lang = language;
    if (ageTier == 'under_15') {
      try {
        await api.post('/v1/learner/onboard', {'lang': lang, 'age_tier': 'under_15'});
      } catch (_) {}
      return false;
    }
    tier = ageTier;
    try {
      await api.post('/v1/learner/onboard', {'lang': lang, 'age_tier': ageTier});
    } catch (_) {}
    onboarded = true;
    await _savePrefs();
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- PIN & quick exit
  String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String? pin) async {
    if (pin == null) {
      _pinHash = null;
      _pinSalt = null;
    } else {
      final r = Random.secure();
      _pinSalt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
      _pinHash = _hash(pin, _pinSalt!);
    }
    await _savePrefs();
    notifyListeners();
  }

  bool checkPin(String pin) => _pinHash != null && _hash(pin, _pinSalt!) == _pinHash;

  void quickExit() {
    disguised = true;
    locked = true;
    history = keepHistory ? history : [];
    notifyListeners();
  }

  void lockIfPin() {
    if (hasPin && onboarded) {
      locked = true;
      notifyListeners();
    }
  }

  bool unlock(String? pin) {
    if (hasPin && (pin == null || !checkPin(pin))) return false;
    locked = false;
    disguised = false;
    notifyListeners();
    return true;
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

  Future<void> setKeepHistory(bool v) async {
    keepHistory = v;
    if (!v) {
      history = [];
      await store.write('history', null);
    }
    await _savePrefs();
    notifyListeners();
  }

  Future<void> addHistory(Map<String, dynamic> item) async {
    history.add(item);
    if (history.length > 30) history.removeAt(0);
    if (keepHistory) await store.write('history', jsonEncode(history));
  }

  // ---------------------------------------------------------------- referrals & follow-up
  Future<void> addReferral(SavedReferral r) async {
    referrals.insert(0, r);
    await _saveRefs();
    notifyListeners();
  }

  Future<void> _saveRefs() => store.write('referrals', jsonEncode(referrals.map((e) => e.toJson()).toList()));

  Future<void> setReminders(SavedReferral r, bool on) async {
    r.reminders = on;
    if (on) {
      await Notifications.scheduleCheckIns(r.code.hashCode & 0x7fffffff, t('followup', 'ping'), t('followup', 'ask'));
      api.post('/v1/learner/events', {'event': 'reminder_opt_in', 'lang': lang, 'tier': tier}).catchError((_) => null);
    } else {
      await Notifications.cancel(r.code.hashCode & 0x7fffffff);
    }
    await _saveRefs();
    notifyListeners();
  }

  Future<Map<String, dynamic>?> recordOutcome(SavedReferral r, String outcome, {String barrier = ''}) async {
    r.outcome = outcome;
    await _saveRefs();
    notifyListeners();
    if (outcome == 'went') await setReminders(r, false);
    try {
      final res = await api.post('/v1/learner/outcome', {'outcome': outcome, 'barrier': barrier, 'lang': lang, 'tier': tier});
      return res as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncConfirmations() async {
    try {
      final res = await api.get('/v1/referrals/mine') as Map<String, dynamic>;
      final confirmed = {for (final r in (res['referrals'] as List)) r['code']: r['confirmed'] == true};
      for (final r in referrals) {
        if (confirmed[r.code] == true) r.confirmed = true;
      }
      await _saveRefs();
      notifyListeners();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- delete my data
  Future<bool> deleteEverything() async {
    bool serverOk = true;
    try {
      await api.delete('/v1/learner/data');
    } catch (_) {
      serverOk = false;
    }
    final oldId = api.installId;
    await Notifications.cancelAll();
    await store.wipe();
    // Only an opaque random id is kept, and only until the server delete succeeds.
    if (!serverOk) await store.write('pending_server_delete', oldId);
    onboarded = false;
    tier = '';
    lang = 'en';
    referrals = [];
    history = [];
    _pinHash = null;
    _pinSalt = null;
    locked = false;
    disguised = false;
    bundle = null;
    await init();
    return serverOk;
  }

  void showCrisis(Map<String, dynamic> payload) {
    pendingCrisis = payload;
    notifyListeners();
  }

  void signOutStaff() {
    staff = null;
    api.staffToken = null;
    notifyListeners();
  }
}
