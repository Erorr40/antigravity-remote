import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const String channelProgress = 'agent_progress';
  static const String channelAwaitingInput = 'awaiting_input';
  static const String channelComplete = 'task_complete';

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification click to navigate to session
      },
    );

    // Initialize Android 13+ granular notification channels
    final androidImplementation = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // 1. Channel: Agent Progress
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelProgress,
          'Agent Progress',
          description: 'Streaming status and thinking updates from Antigravity',
          importance: Importance.low,
          enableVibration: false,
          showBadge: false,
        ),
      );

      // 2. Channel: Awaiting Input
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelAwaitingInput,
          'Awaiting Input',
          description: 'Prompts, questions, and tool confirmations needing your approval',
          importance: Importance.high,
          enableVibration: true,
          showBadge: true,
        ),
      );

      // 3. Channel: Task Complete
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          channelComplete,
          'Task Complete',
          description: 'Alerts when long-running agent tasks finish or error',
          importance: Importance.max,
          enableVibration: true,
          showBadge: true,
        ),
      );

      // Request runtime POST_NOTIFICATIONS permission on Android 13+
      await androidImplementation.requestNotificationsPermission();
    }
  }

  Future<void> showTaskComplete({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelComplete,
      'Task Complete',
      channelDescription: 'Alerts when long-running agent tasks finish',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  Future<void> showAwaitingInput({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelAwaitingInput,
      'Awaiting Input',
      channelDescription: 'Prompts and tool confirmations',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  Future<void> showProgress({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelProgress,
      'Agent Progress',
      channelDescription: 'Streaming status and thinking updates',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}
