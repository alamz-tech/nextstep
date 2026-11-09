import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device follow-up reminders (day 3 and day 7). No server push, no
/// WhatsApp templates. The text is neutral: it never mentions health.
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('checkins', 'Reminders',
        channelDescription: 'Occasional check-ins', importance: Importance.defaultImportance,
        visibility: NotificationVisibility.secret),
  );

  static Future<bool> scheduleCheckIns(int baseId, String title, String body) async {
    if (kIsWeb) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final now = tz.TZDateTime.now(tz.UTC);
    for (final (i, days) in [(0, 3), (1, 7)]) {
      // 10:00 West Africa Time (09:00 UTC) on day 3 and day 7.
      final d = now.add(Duration(days: days));
      final when = tz.TZDateTime.utc(d.year, d.month, d.day, 9);
      await _plugin.zonedSchedule((baseId + i) & 0x7fffffff, title, body, when, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
    return true;
  }

  static Future<void> cancel(int baseId) async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancel(baseId & 0x7fffffff);
    await _plugin.cancel((baseId + 1) & 0x7fffffff);
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
  }
}
