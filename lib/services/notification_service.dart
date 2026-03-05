import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';

/// Port name cho IsolateNameServer - giao tiếp giữa background và foreground
const String waterAlarmPortName = 'water_alarm_port';

// Callback cho notification tap
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse response) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Log để debug
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_notification_tap', 
      '${DateTime.now()}: actionId=${response.actionId}, payload=${response.payload}');
    
    debugPrint('notificationTapBackground called: actionId=${response.actionId}, payload=${response.payload}');
    
    if (response.actionId == 'snooze' && response.payload == 'water_reminder') {
      debugPrint('Snooze action triggered');
      await prefs.setString('snooze_debug', '${DateTime.now()}: Starting snooze');
      await _scheduleSnoozeInBackground();
      await prefs.setString('snooze_debug', '${DateTime.now()}: Snooze scheduled');
    } else if (response.actionId == 'drink_now' && response.payload == 'water_reminder') {
      debugPrint('Drink now action triggered');
      await _cancelSnoozeInBackground();
    }
  } catch (e) {
    debugPrint('notificationTapBackground error: $e');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snooze_error', '${DateTime.now()}: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _scheduleSnoozeInBackground() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snooze_step', '${DateTime.now()}: Step 1 - Init');
    
    final notifications = FlutterLocalNotificationsPlugin();
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
    await notifications.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    await prefs.setString('snooze_step', '${DateTime.now()}: Step 2 - Cancel old');
    await notifications.cancel(0);
    
    await prefs.setBool('water_snooze_active', true);
    // Set block flag
    await prefs.setBool('block_alarm_screen', true);
    await prefs.setBool('pending_water_dialog', false);
    
    await prefs.setString('snooze_step', '${DateTime.now()}: Step 3 - Show notification');
    
    // Hiện notification trên thanh báo thời gian snooze (iOS: 1 phút, Android: 20 giây)
    final snoozeText = Platform.isIOS ? '1 phút' : '20 giây';
    final mode = prefs.getString('water_notification_mode') ?? 'both';
    bool playSound = mode == 'sound' || mode == 'both';
    bool enableVibration = mode == 'vibrate' || mode == 'both';
    
    const drinkAction = AndroidNotificationAction(
      'drink_now',
      'Uống ngay',
      showsUserInterface: true,
    );
    
    final snoozeNotifDetails = AndroidNotificationDetails(
      'water_snooze_v11_$mode',
      'Nhắc nhở uống nước (để sau)',
      channelDescription: 'Thông báo nhắc nhở sau khi bấm để sau',
      importance: Importance.max,
      priority: Priority.max,
      playSound: playSound,
      enableVibration: enableVibration,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[drinkAction],
      styleInformation: BigTextStyleInformation(
        'Sẽ nhắc lại sau $snoozeText',
        contentTitle: 'Nhắc nhở uống nước',
      ),
    );
    const iosSnoozeDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(
      android: snoozeNotifDetails,
      iOS: iosSnoozeDetails,
    );
    await notifications.show(
      0,
      'Nhắc nhở uống nước',
      'Sẽ nhắc lại sau $snoozeText',
      details,
      payload: 'water_reminder',
    );
    
    if (!kIsWeb && Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
      await AndroidAlarmManager.oneShot(
        const Duration(seconds: 20),
        98,
        snoozeAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
      );
    } else if (!kIsWeb && Platform.isIOS) {
      // iOS: dùng zonedSchedule thay vì AndroidAlarmManager
      // iOS yêu cầu tối thiểu 60 giây
      tz_data.initializeTimeZones();
      final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 60));
      const iosReminderDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: 'water_reminder',
      );
      final reminderDetails = NotificationDetails(iOS: iosReminderDetails);
      await notifications.zonedSchedule(
        98,
        'Nhắc lại uống nước',
        'Bấm "Uống ngay" hoặc "Để sau"',
        snoozeTime,
        reminderDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'water_reminder',
      );
    }
    
    await prefs.setString('snooze_step', '${DateTime.now()}: Step 4 - Alarm scheduled DONE');
  } catch (e) {
    debugPrint('_scheduleSnoozeInBackground error: $e');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snooze_error', '${DateTime.now()}: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _cancelSnoozeInBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final notifications = FlutterLocalNotificationsPlugin();
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
  await notifications.initialize(initSettings);
  await notifications.cancel(0);
  await notifications.cancel(98); // Cancel scheduled snooze
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('water_snooze_active', false);
  await prefs.setBool('pending_water_dialog', false);
  
  if (!kIsWeb && Platform.isAndroid) {
    await AndroidAlarmManager.initialize();
    await AndroidAlarmManager.cancel(98);
  }
}

/// Tạo notification details dựa trên chế độ âm thanh
/// Dùng channel ID riêng cho mỗi mode để tránh Android cache channel settings
Future<AndroidNotificationDetails> _buildNotificationDetails(String title) async {
  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('water_notification_mode') ?? 'both';
  
  bool playSound;
  bool enableVibration;
  bool useFullScreen;
  
  switch (mode) {
    case 'sound':
      playSound = true;
      enableVibration = false;
      useFullScreen = true;
      break;
    case 'vibrate':
      playSound = false;
      enableVibration = true;
      useFullScreen = true;
      break;
    case 'both':
      playSound = true;
      enableVibration = true;
      useFullScreen = true;
      break;
    case 'silent':
      playSound = false;
      enableVibration = false;
      useFullScreen = false;
      break;
    default:
      playSound = true;
      enableVibration = true;
      useFullScreen = true;
  }
  
  const drinkAction = AndroidNotificationAction(
    'drink_now',
    'Uống ngay',
    showsUserInterface: true,
    cancelNotification: true,
  );
  
  const snoozeAction = AndroidNotificationAction(
    'snooze',
    'Để sau',
    showsUserInterface: true,
    cancelNotification: true,
  );
  
  // Dùng channel ID version mới để Android tạo channel mới với settings đúng
  // Thêm timestamp để buộc Android tạo channel mới mỗi lần đổi mode
  final channelId = 'water_alarm_v11_$mode';
  final channelName = 'Nhắc nhở uống nước ($mode)';
  
  return AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: 'Thông báo nhắc nhở uống nước - chế độ $mode',
    importance: Importance.max,
    priority: Priority.max,
    playSound: playSound,
    enableVibration: enableVibration,
    fullScreenIntent: useFullScreen,
    category: useFullScreen ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
    visibility: NotificationVisibility.public,
    enableLights: true,
    ongoing: true,
    autoCancel: false,
    actions: <AndroidNotificationAction>[drinkAction, snoozeAction],
    styleInformation: BigTextStyleInformation(
      'Bấm "Uống ngay" hoặc "Để sau"',
      contentTitle: title,
    ),
  );
}

// Callback cho snooze alarm
@pragma('vm:entry-point')
Future<void> snoozeAlarmCallback() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    final prefs = await SharedPreferences.getInstance();
    final snoozeActive = prefs.getBool('water_snooze_active') ?? false;
    if (!snoozeActive) return;
    
    // Reset snooze flag
    await prefs.setBool('water_snooze_active', false);
    await prefs.setBool('pending_water_dialog', true);
    // Reset block flag để alarm screen có thể hiện
    await prefs.setBool('block_alarm_screen', false);
    
    // Snooze fire → hiện notification
    final notifications = FlutterLocalNotificationsPlugin();
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
    await notifications.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    final mode = prefs.getString('water_notification_mode') ?? 'both';
    bool playSound = mode == 'sound' || mode == 'both';
    bool enableVibration = mode == 'vibrate' || mode == 'both';
    // Silent mode: không hiện màn hình vàng đen
    bool useFullScreen = mode != 'silent';
    
    const drinkAction = AndroidNotificationAction(
      'drink_now',
      'Uống ngay',
      showsUserInterface: true,
      cancelNotification: true,
    );
    
    const snoozeAction = AndroidNotificationAction(
      'snooze',
      'Để sau',
      showsUserInterface: true,
      cancelNotification: true,
    );
    
    final androidDetails = AndroidNotificationDetails(
      'water_alarm_v11_$mode',
      'Nhắc nhở uống nước ($mode)',
      channelDescription: 'Thông báo nhắc nhở uống nước',
      importance: Importance.max,
      priority: Priority.max,
      playSound: playSound,
      enableVibration: enableVibration,
      fullScreenIntent: useFullScreen, // Chỉ hiện màn hình vàng đen nếu KHÔNG phải silent
      category: useFullScreen ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[drinkAction, snoozeAction],
      styleInformation: const BigTextStyleInformation(
        'Bấm "Uống ngay" hoặc "Để sau"',
        contentTitle: 'Nhắc lại uống nước',
      ),
    );
    const iosSnoozeDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosSnoozeDetails,
    );
    
    await notifications.show(
      0,
      'Nhắc lại uống nước',
      'Bấm "Uống ngay" hoặc "Để sau"',
      details,
      payload: 'water_reminder',
    );
    
    // Notify main isolate nếu app đang mở (chỉ khi không phải silent)
    if (useFullScreen) {
      _notifyMainIsolate();
    }
  } catch (e) {
    debugPrint('snoozeAlarmCallback error: $e');
  }
}

// Callback cho alarm manager chính
@pragma('vm:entry-point')
Future<void> alarmCallback() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('water_reminder_enabled') ?? false;
    if (!enabled) return;
    
    await prefs.setBool('water_snooze_active', false);
    await prefs.setBool('pending_water_dialog', true);
    // Reset block flag để alarm screen có thể hiện
    await prefs.setBool('block_alarm_screen', false);
    
    // LUÔN hiện notification (kể cả khi app đang mở)
    // Nếu app ở foreground → main isolate sẽ cancel notification + hiện alarm screen
    // Nếu app ở background/đóng → notification + fullScreenIntent xử lý
    final notifications = FlutterLocalNotificationsPlugin();
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
    await notifications.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    final androidDetails = await _buildNotificationDetails('Đã đến giờ uống nước');
    const iosAlarmDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosAlarmDetails,
    );
    
    await notifications.show(
      0,
      'Đã đến giờ uống nước',
      'Bấm "Để sau" hoặc "Uống ngay"',
      details,
      payload: 'water_reminder',
    );
    
    // Gửi signal đến main isolate (nếu app đang ở foreground → hiện alarm screen trực tiếp)
    _notifyMainIsolate();
  } catch (e) {
    debugPrint('alarmCallback error: $e');
  }
}

/// Gửi signal đến main isolate. Trả về true nếu app đang mở
bool _notifyMainIsolate() {
  final sendPort = IsolateNameServer.lookupPortByName(waterAlarmPortName);
  if (sendPort != null) {
    sendPort.send('show_alarm');
    return true;
  }
  return false;
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  static final StreamController<String?> _onNotificationTap = StreamController<String?>.broadcast();
  static Stream<String?> get onNotificationTap => _onNotificationTap.stream;
  
  // Stream cho alarm - hiện WaterAlarmScreen khi alarm kích hoạt
  static final StreamController<void> _onAlarmFired = StreamController<void>.broadcast();
  static Stream<void> get onAlarmFired => _onAlarmFired.stream;
  
  static String? pendingPayload;
  
  /// Block alarm screen - dùng SharedPreferences thay vì static variable
  /// để share state giữa các isolate
  static bool blockAlarmUntilNextAlarm = false; // Kept for backward compat, but use prefs
  
  bool _initialized = false;
  ReceivePort? _alarmReceivePort;
  
  /// Kiểm tra nhanh app có được launch từ notification không
  /// Gọi TRƯỚC Firebase.init để biết ngay có cần hiện alarm screen hay không
  Future<bool> checkAlarmLaunch() async {
    if (kIsWeb) return false;
    
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
    
    // Init plugin nhẹ (không cần callback đầy đủ ở đây, sẽ re-init trong initialize())
    await _notifications.initialize(initSettings);
    
    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails?.notificationResponse;
      if (response?.actionId == 'drink_now') {
        pendingPayload = 'water_drink_tab';
      } else if (response?.actionId == 'snooze') {
        pendingPayload = 'water_snooze';
      } else {
        pendingPayload = 'water_alarm_screen';
      }
      return pendingPayload == 'water_alarm_screen';
    }
    return false;
  }
  
  /// Xử lý khi app được launch từ nút "Để sau" notification
  /// Sau khi xử lý xong, app sẽ thoát ngay không hiện UI
  Future<void> handleSnoozeLaunchAndExit() async {
    if (kIsWeb) return;
    
    try {
      // Clear pending payload
      pendingPayload = null;
      
      // Cancel notification hiện tại
      await _notifications.cancel(0);
      
      // Lưu trạng thái snooze
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('water_snooze_active', true);
      
      if (Platform.isAndroid) {
        // Lấy chế độ âm thanh hiện tại
        final mode = prefs.getString('water_notification_mode') ?? 'both';
        bool playSound = mode == 'sound' || mode == 'both';
        bool enableVibration = mode == 'vibrate' || mode == 'both';
        
        const drinkAction = AndroidNotificationAction(
          'drink_now',
          'Uống ngay',
          showsUserInterface: true,
        );
        
        // Hiện notification popup "Sẽ nhắc lại sau 20 giây"
        final snoozeNotifDetails = AndroidNotificationDetails(
          'water_snooze_v11_$mode',
          'Nhắc nhở uống nước (để sau)',
          channelDescription: 'Thông báo nhắc nhở sau khi bấm để sau',
          importance: Importance.max,
          priority: Priority.max,
          playSound: playSound,
          enableVibration: enableVibration,
          fullScreenIntent: false,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          ongoing: true,
          autoCancel: false,
          actions: <AndroidNotificationAction>[drinkAction],
          styleInformation: const BigTextStyleInformation(
            'Sẽ nhắc lại sau 20 giây',
            contentTitle: 'Nhắc nhở uống nước',
          ),
        );
        final details = NotificationDetails(android: snoozeNotifDetails);
        await _notifications.show(
          0,
          'Nhắc nhở uống nước',
          'Sẽ nhắc lại sau 20 giây',
          details,
          payload: 'water_reminder',
        );
        
        // Lên lịch snooze alarm sau 20 giây
        await AndroidAlarmManager.initialize();
        await AndroidAlarmManager.oneShot(
          const Duration(seconds: 20),
          98,
          snoozeAlarmCallback,
          exact: true,
          wakeup: true,
          allowWhileIdle: true,
        );
      } else if (Platform.isIOS) {
        // iOS: hiện notification "sẽ nhắc lại" và lên lịch snooze bằng zonedSchedule
        // iOS yêu cầu tối thiểu 60 giây
        const iosSnoozeDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: 'water_reminder',
        );
        final details = NotificationDetails(iOS: iosSnoozeDetails);
        await _notifications.show(
          0,
          'Nhắc nhở uống nước',
          'Sẽ nhắc lại sau 1 phút',
          details,
          payload: 'water_reminder',
        );
        
        // Lên lịch snooze notification sau 60 giây (iOS minimum)
        tz_data.initializeTimeZones();
        final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 60));
        const iosReminderDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
          categoryIdentifier: 'water_reminder',
        );
        final reminderDetails = NotificationDetails(iOS: iosReminderDetails);
        await _notifications.zonedSchedule(
          98,
          'Nhắc lại uống nước',
          'Bấm "Uống ngay" hoặc "Để sau"',
          snoozeTime,
          reminderDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'water_reminder',
        );
        debugPrint('🍎 iOS: Snooze scheduled for 60s at ${snoozeTime.toString()}');
      }
    } catch (e) {
      debugPrint('handleSnoozeLaunchAndExit error: $e');
    }
  }
  
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;
    
    tz_data.initializeTimeZones();
    
    // Đăng ký port để nhận signal từ background alarm callback
    _setupAlarmPort();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'water_reminder',
          actions: [
            DarwinNotificationAction.plain('drink_now', 'Uống ngay',
              options: {DarwinNotificationActionOption.foreground}),
            DarwinNotificationAction.plain('snooze', 'Để sau',
              options: {DarwinNotificationActionOption.foreground}),
          ],
        ),
      ],
    );
    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        debugPrint('FOREGROUND callback: actionId=${response.actionId}, payload=${response.payload}');
        
        // Log để debug
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('foreground_callback', 
          '${DateTime.now()}: actionId=${response.actionId}');
        
        if (response.payload == 'water_reminder') {
          if (response.actionId == 'snooze') {
            // Để sau: hủy notification, set block flag, hiện popup trên thanh, lên lịch snooze
            debugPrint('SNOOZE action in foreground');
            await prefs.setString('snooze_foreground', '${DateTime.now()}: Starting snooze');
            
            _instance._notifications.cancel(0);
            
            // Set block flag trong SharedPreferences
            await prefs.setBool('block_alarm_screen', true);
            await prefs.setBool('pending_water_dialog', false);
            
            await _instance.scheduleSnooze();
            final snoozeText = Platform.isIOS ? '1 phút' : '20 giây';
            await _instance.showSimpleNotification(
              title: 'Nhắc nhở uống nước',
              body: 'Sẽ nhắc lại sau $snoozeText',
              payload: 'water_reminder',
            );
            
            await prefs.setString('snooze_foreground', '${DateTime.now()}: Snooze done');
          } else if (response.actionId == 'drink_now') {
            // Uống ngay → vào tab uống nước
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('block_alarm_screen', true);
            await prefs.setBool('pending_water_dialog', false);
            
            _onNotificationTap.add('water_drink_tab');
            _instance._notifications.cancel(0);
            _instance.cancelSnooze();
          } else {
            // Tap notification body (không có actionId) → hiện alarm screen
            _instance._notifications.cancel(0);
            _onAlarmFired.add(null);
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails?.notificationResponse;
      if (response?.actionId == 'drink_now') {
        // User bấm "Uống ngay" → vào tab uống nước
        pendingPayload = 'water_drink_tab';
      } else if (response?.actionId == 'snooze') {
        // User bấm "Để sau"
        pendingPayload = 'water_snooze';
      } else {
        // fullScreenIntent tự launch app hoặc tap notification body
        // → hiện alarm screen
        pendingPayload = 'water_alarm_screen';
      }
    }
    
    if (!kIsWeb && Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
    }
    
    _initialized = true;
  }
  
  /// Đăng ký ReceivePort để nhận signal từ alarm callback
  void _setupAlarmPort() {
    IsolateNameServer.removePortNameMapping(waterAlarmPortName);
    _alarmReceivePort?.close();
    
    _alarmReceivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _alarmReceivePort!.sendPort,
      waterAlarmPortName,
    );
    
    _alarmReceivePort!.listen((_) {
      // Reset block flag khi có alarm mới
      blockAlarmUntilNextAlarm = false;
      
      // Chỉ xử lý nếu app đang ở FOREGROUND (resumed)
      // Nếu app ở background → để notification + fullScreenIntent xử lý
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState == AppLifecycleState.resumed) {
        // App ở foreground → cancel notification và hiện alarm screen trực tiếp
        _notifications.cancel(0);
        _onAlarmFired.add(null);
      }
      // Nếu app ở background: không cancel notification
      // pending_water_dialog đã được set, khi app resume sẽ hiện alarm screen
    });
  }
  
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } else if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }
  
  Future<void> scheduleSnooze() async {
    if (kIsWeb) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('water_snooze_active', true);
    
    if (Platform.isAndroid) {
      await AndroidAlarmManager.oneShot(
        const Duration(seconds: 20),
        98,
        snoozeAlarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
      );
      debugPrint('🔔 Android: Snooze scheduled for 20s');
    } else if (Platform.isIOS) {
      // iOS: yêu cầu tối thiểu 60 giây cho zonedSchedule
      final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 60));
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: 'water_reminder',
      );
      final details = NotificationDetails(iOS: iosDetails);
      await _notifications.zonedSchedule(
        98,
        'Nhắc lại uống nước',
        'Bấm "Uống ngay" hoặc "Để sau"',
        snoozeTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'water_reminder',
      );
      debugPrint('🍎 iOS: Snooze scheduled for 60s at ${snoozeTime.toString()}');
    }
  }
  
  Future<void> cancelSnooze() async {
    if (kIsWeb) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('water_snooze_active', false);
    await prefs.setBool('pending_water_dialog', false);
    
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(98);
    }
    // iOS: cancel scheduled snooze notification
    await _notifications.cancel(98);
  }
  
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    
    final androidDetails = await _buildNotificationDetails(title);
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(0, title, body, details, payload: payload);
  }
  
  /// Hiện notification popup trên thanh thông báo khi bấm "Để sau"
  /// Có heads-up display + action buttons
  Future<void> showSimpleNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;
    
    // Lấy chế độ âm thanh hiện tại
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('water_notification_mode') ?? 'both';
    
    bool playSound;
    bool enableVibration;
    
    switch (mode) {
      case 'sound':
        playSound = true;
        enableVibration = false;
        break;
      case 'vibrate':
        playSound = false;
        enableVibration = true;
        break;
      case 'both':
        playSound = true;
        enableVibration = true;
        break;
      case 'silent':
        playSound = false;
        enableVibration = false;
        break;
      default:
        playSound = true;
        enableVibration = true;
    }
    
    const drinkAction = AndroidNotificationAction(
      'drink_now',
      'Uống ngay',
      showsUserInterface: true,
    );
    
    final androidDetails = AndroidNotificationDetails(
      'water_snooze_v11_$mode',
      'Nhắc nhở uống nước (để sau)',
      channelDescription: 'Thông báo nhắc nhở sau khi bấm để sau',
      importance: Importance.max,
      priority: Priority.max,
      playSound: playSound,
      enableVibration: enableVibration,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[drinkAction],
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(0, title, body, details, payload: payload);
  }
  
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    if (kIsWeb) return;
    
    final androidDetails = await _buildNotificationDetails(title);
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'water_reminder',
    );
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }
  
  Future<void> schedulePeriodicNotification({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    String? payload,
  }) async {
    if (kIsWeb) return;
    
    // iOS yêu cầu interval tối thiểu 60 giây
    Duration adjustedInterval = interval;
    if (Platform.isIOS && interval.inSeconds < 60) {
      adjustedInterval = const Duration(seconds: 60);
      debugPrint('⚠️ iOS: Adjusted interval from ${interval.inSeconds}s to 60s (minimum)');
    }
    
    debugPrint('🔔 schedulePeriodicNotification:');
    debugPrint('   Platform: ${Platform.isIOS ? "iOS" : "Android"}');
    debugPrint('   Interval: ${adjustedInterval.inSeconds}s');
    
    await cancelAll();
    await cancelSnooze();
    if (Platform.isAndroid) {
      await AndroidAlarmManager.cancel(99);
    }
    
    if (Platform.isAndroid) {
      await AndroidAlarmManager.periodic(
        adjustedInterval,
        99,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      debugPrint('✅ Android AlarmManager periodic set');
    }
    
    final now = DateTime.now();
    // iOS giới hạn 64 pending notifications, dùng tối đa 50 để chừa chỗ cho snooze
    final maxCount = (!kIsWeb && Platform.isIOS) ? 50 : (adjustedInterval.inSeconds < 120 ? 48 : 24);
    int scheduled = 0;
    for (int i = 1; i <= maxCount * 2 && scheduled < maxCount; i++) {
      final scheduledTime = now.add(adjustedInterval * i);
      if (scheduledTime.hour >= 6 && scheduledTime.hour < 22) {
        await scheduleNotification(
          id: 1000 + i,
          title: title,
          body: body,
          scheduledTime: scheduledTime,
          payload: payload,
        );
        scheduled++;
        if (scheduled <= 3) {
          debugPrint('   [$scheduled] Scheduled for: ${scheduledTime.toString()}');
        }
      }
    }
    
    debugPrint('✅ Total scheduled: $scheduled notifications');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_reminder_interval_seconds', adjustedInterval.inSeconds);
    await prefs.setBool('water_reminder_enabled', true);
    // Lưu checkpoint cho iOS
    await prefs.setInt('ios_last_alarm_check_ms', now.millisecondsSinceEpoch);
  }
  
  Future<void> cancelNotification(int id) async {
    if (kIsWeb) return;
    await _notifications.cancel(id);
  }
  
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _notifications.cancelAll();
  }
  
  Future<void> rescheduleWaterReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('water_reminder_enabled') ?? false;
    final intervalSeconds = prefs.getInt('water_reminder_interval_seconds') ?? 1800;
    
    if (enabled) {
      await schedulePeriodicNotification(
        id: 1,
        title: 'Đã đến giờ uống nước',
        body: 'Uống nước ngay!',
        interval: Duration(seconds: intervalSeconds),
        payload: 'water_reminder',
      );
    }
  }
  
  /// iOS: Kiểm tra xem có notification nào đã fire (theo lịch) chưa được xử lý không
  /// Gọi khi app resume để hiện alarm screen nếu cần
  Future<bool> checkIOSPendingAlarm() async {
    if (kIsWeb || !Platform.isIOS) return false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    
    final enabled = prefs.getBool('water_reminder_enabled') ?? false;
    if (!enabled) return false;
    
    final blocked = prefs.getBool('block_alarm_screen') ?? false;
    if (blocked) return false;
    
    // Kiểm tra thời gian scheduled gần nhất có đã qua chưa
    final lastCheckMs = prefs.getInt('ios_last_alarm_check_ms') ?? 0;
    final intervalSeconds = prefs.getInt('water_reminder_interval_seconds') ?? 1800;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Nếu đã qua > interval từ lần check cuối, có thể có alarm chưa xử lý
    if (lastCheckMs > 0 && (now - lastCheckMs) >= (intervalSeconds * 1000)) {
      // Cập nhật checkpoint
      await prefs.setInt('ios_last_alarm_check_ms', now);
      return true;
    }
    
    // Cập nhật checkpoint nếu chưa có
    if (lastCheckMs == 0) {
      await prefs.setInt('ios_last_alarm_check_ms', now);
    }
    
    return false;
  }
  
  Future<void> stopWaterReminder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('water_reminder_enabled', false);
    await prefs.setBool('water_snooze_active', false);
    await prefs.setBool('pending_water_dialog', false);
    await cancelAll();
    if (!kIsWeb && Platform.isAndroid) {
      await AndroidAlarmManager.cancel(99);
      await AndroidAlarmManager.cancel(98);
    }
  }
}
