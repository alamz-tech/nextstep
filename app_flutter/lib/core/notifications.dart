import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device check-ins (day 3 and day 7). Neutral text from the design
/// (followup.ping), hidden on the lock screen. No server push.
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
        importance: Importance.defaultImportance, visibility: NotificationVisibility.secret),
  );

  static Future<void> scheduleCheckIns(String title, String body) async {
    if (kIsWeb) return;
    await init();
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    final now = tz.TZDateTime.now(tz.UTC);
    for (final (id, days) in [(3, 3), (7, 7)]) {
      final d = now.add(Duration(days: days));
      // 10:00 West Africa Time = 09:00 UTC (design: send 10:00–18:00 WAT).
      await _plugin.zonedSchedule(id, title, body, tz.TZDateTime.utc(d.year, d.month, d.day, 9), _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
  }
}
