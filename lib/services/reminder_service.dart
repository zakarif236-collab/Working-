import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:my_app/services/settings_service.dart';

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    await _requestPermissions();
    _initialized = true;
  }

  Future<void> maybeSendDailyWorkoutReminder(SettingsService settingsService) async {
    await initialize();

    final shouldSend = await settingsService.shouldSendMissedWorkoutReminder();
    if (!shouldSend) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'workout_reminders',
        'Workout Reminders',
        channelDescription: 'Helps users stay consistent with workout streaks',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _notifications.show(
      9001,
      'Daily workout reminder',
      'Time to move. Start your workout today and keep getting fitter.',
      details,
    );

    await settingsService.markReminderSent();
  }

  Future<void> maybeSendMissedWorkoutReminder(SettingsService settingsService) {
    return maybeSendDailyWorkoutReminder(settingsService);
  }

  Future<void> _requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final macos = _notifications.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macos?.requestPermissions(alert: true, badge: true, sound: true);
  }
}
