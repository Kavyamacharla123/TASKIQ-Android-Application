import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  /// Initialize notifications + timezone
  static Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
    InitializationSettings(android: androidSettings);

    await _flutterLocalNotificationsPlugin.initialize(settings);
    // 🔥 ADD THIS FOR ANDROID 13+
    final androidImplementation = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  /// Cancel scheduled notification
  static Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  /// Schedule notification (FIXED)
  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final tz.TZDateTime tzTime =
    tz.TZDateTime.from(scheduledTime, tz.local);

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'task_channel',
      'Task Notifications',
      channelDescription: 'Task reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails details =
    NotificationDetails(android: androidDetails);

    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null,
      );
    } catch (e) {
      print("Notification Error: $e");
    }
  }

  /// Schedule repeated daily notification
  static Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required DateTime timeOfDay,
  }) async {
    final tz.TZDateTime tzTime = tz.TZDateTime(tz.local, timeOfDay.year, timeOfDay.month, timeOfDay.day, timeOfDay.hour, timeOfDay.minute);

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails('daily_channel', 'Daily Reminders', channelDescription: 'Daily habit reminders', importance: Importance.max, priority: Priority.high),
    );

    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    try {
        await _flutterLocalNotificationsPlugin.zonedSchedule(
          id, title, body, tzTime, details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
    } catch (e) {
        print("Daily Notification Error: $e");
    }
  }

  /// Instant notification (useful for location triggers or snooze)
  static Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails('instant_channel', 'Instant Notifications', importance: Importance.max, priority: Priority.high),
    );
    await _flutterLocalNotificationsPlugin.show(id, title, body, details);
  }
}
