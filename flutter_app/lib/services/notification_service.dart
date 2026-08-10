import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:intl/intl.dart';

/// Wraps flutter_local_notifications and always formats/labels timestamps
/// in Asia/Kolkata (IST), regardless of the device's own timezone.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  late final tz.Location _kolkata;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    _kolkata = tz.getLocation('Asia/Kolkata');

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    // Android 13+ needs explicit runtime permission.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  String get _kolkataTimeLabel {
    final nowIst = tz.TZDateTime.now(_kolkata);
    return DateFormat('hh:mm a').format(nowIst) + ' IST';
  }

  Future<void> notifyCompleted(String filename) async {
    await _show(
      title: 'Download completed',
      body: '$filename • $_kolkataTimeLabel',
    );
  }

  Future<void> notifyPaused(String reason) async {
    await _show(
      title: 'Download paused',
      body: '$reason • $_kolkataTimeLabel',
    );
  }

  Future<void> notifyFailed(String reason) async {
    await _show(
      title: 'Download failed',
      body: '$reason • $_kolkataTimeLabel',
    );
  }

  Future<void> _show({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'downloads_channel',
      'Downloads',
      channelDescription: 'Notifications about YouTube download progress',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
