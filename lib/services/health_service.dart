import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';
import 'package:health/health.dart';
import 'firestore_service.dart';

enum StepsRefreshStatus { success, permissionDenied, noData, error }

class StepsRefreshResult {
  final StepsRefreshStatus status;
  final int? steps;
  final String? error;

  const StepsRefreshResult._(this.status, {this.steps, this.error});

  bool get isSuccess => status == StepsRefreshStatus.success;

  factory StepsRefreshResult.success(int steps) =>
      StepsRefreshResult._(StepsRefreshStatus.success, steps: steps);

  factory StepsRefreshResult.permissionDenied() =>
      StepsRefreshResult._(StepsRefreshStatus.permissionDenied);

  factory StepsRefreshResult.noData() =>
      StepsRefreshResult._(StepsRefreshStatus.noData);

  factory StepsRefreshResult.error(String error) =>
      StepsRefreshResult._(StepsRefreshStatus.error, error: error);
}

/// Service quản lý sức khỏe: bước chân, giấc ngủ, cân nặng, sinh nhật
class HealthService {
  static final HealthService _instance = HealthService._();
  HealthService._();
  factory HealthService() => _instance;

  static const Duration _realtimeReconcileInterval = Duration(seconds: 1);
  static const Duration _historySyncInterval = Duration(seconds: 20);

  static const MethodChannel _channel = MethodChannel('com.betterme.betterme/app');

  final Health _health = Health();
  bool _healthConfigured = false;

  StreamSubscription<StepCount>? _stepSubscription;
  final _stepsController = StreamController<int>.broadcast();
  Stream<int> get stepsStream => _stepsController.stream;

  int _todaySteps = 0;
  int get todaySteps => _todaySteps;

  int? _lastSavedSteps;
  int? _lastRawSteps;
  Timer? _saveDebounceTimer;
  Timer? _reconcileTimer;
  DateTime? _lastHistoryPersistAt;
  bool _isReconciling = false;
  final bool _legacySensorCountingEnabled = false;
  double _pendingDistanceMetersForSteps = 0;

  bool _initialized = false;

  /// Reset state khi đăng xuất — để re-sync Firestore cho user mới
  void resetForLogout() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    _todaySteps = 0;
    _lastSavedSteps = null;
    _lastRawSteps = null;
    _lastHistoryPersistAt = null;
    _isReconciling = false;
    _initialized = false; // Cho phép init() chạy lại
    _stepsController.add(0);
  }

  /// Khởi tạo step counter
  Future<void> init() async {
    if (kIsWeb) return;

    // Phần sync Firestore: LUÔN chạy lại mỗi khi đăng nhập/init
    await _loadTodaySteps();
    debugPrint('[HealthService.init] _todaySteps sau _loadTodaySteps: $_todaySteps, _initialized=$_initialized');

    // Sync dữ liệu từ Firestore nếu local trống (sau cài lại app / đổi tài khoản)
    await _syncFromFirestore();
    await _syncTodayStepsFromFirestore();
    debugPrint('[HealthService.init] _todaySteps sau sync Firestore: $_todaySteps');

    // Đẩy local steps lên Firestore để tránh mất dữ liệu khi đăng xuất/đăng nhập
    await _syncLocalStepsToFirestore();

    // Cố gắng refresh steps từ Health (iOS sẽ yêu cầu quyền lần đầu)
    await refreshStepsFromHealth(
      requestPermission: !kIsWeb && Platform.isIOS,
    );
    debugPrint('[HealthService.init] _todaySteps sau refreshHealth: $_todaySteps');
    await _backfillMissedDaysSteps();

    // Phần pedometer: chỉ khởi tạo 1 lần
    if (!_initialized) {
      bool canStart = true;
      if (!kIsWeb && Platform.isAndroid) {
        canStart = await _ensureActivityRecognitionPermission();
        if (!canStart) {
          debugPrint('Activity recognition permission not granted; step counter not started.');
        }
      }
      if (canStart) {
        _startListening();
        _initialized = true;
      }
    }
  }

  /// Khôi phục dữ liệu bước chân của 7 ngày trước (trong trường hợp user mở máy mà không vào app, dẫn tới mất sync)
  Future<void> _backfillMissedDaysSteps() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _ensureHealthConfigured();

      final now = DateTime.now();
      
      for (int i = 1; i <= 7; i++) {
        final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final end = DateTime(now.year, now.month, now.day).subtract(Duration(days: i - 1));
        final dateKey = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

        // Kiểm tra xem lịch sử ngày này đã có chưa
        final history = prefs.getStringList('steps_history') ?? [];
        bool hasGoodData = false;
        for (final entry in history) {
          if (entry.startsWith('$dateKey|')) {
            final parts = entry.split('|');
            if (parts.length == 2 && (int.tryParse(parts[1]) ?? 0) > 0) {
              hasGoodData = true;
            }
            break;
          }
        }

        if (!hasGoodData) {
          try {
            final steps = await _health.getTotalStepsInInterval(start, end);
            if (steps != null && steps > 0) {
              await _upsertStepsHistoryEntry(prefs, dateKey, steps);
              await FirestoreService().saveHealthDaily(
                dateKey: dateKey,
                steps: steps,
              );
              debugPrint('BACKFILLED missed steps for $dateKey: $steps');
            }
          } catch (e) {
            debugPrint('Backfill error for $dateKey: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Sync missed days error: $e');
    }
  }

  /// Đồng bộ TẤT CẢ dữ liệu sức khỏe từ Firestore nếu local trống (sau cài lại app / đổi tài khoản)
  Future<void> _syncFromFirestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fs = FirestoreService();

      // Sync chiều cao
      if (!prefs.containsKey('user_height_cm')) {
        final height = await fs.loadHeight();
        if (height != null) {
          await prefs.setDouble('user_height_cm', height);
        }
      }

      // Sync sinh nhật
      if ((prefs.getStringList('birthdays') ?? []).isEmpty) {
        final birthdays = await fs.loadBirthdays();
        if (birthdays.isNotEmpty) {
          final list = birthdays.map((b) => '${b['name']}|${b['date']}').toList();
          await prefs.setStringList('birthdays', list);
        }
      }

      // Sync lịch sử sức khỏe (steps, sleep, weight) — 365 ngày
      final localStepsHistory = prefs.getStringList('steps_history') ?? [];
      final hasPositiveLocalSteps = localStepsHistory.any((entry) {
        final parts = entry.split('|');
        if (parts.length != 2) return false;
        final value = int.tryParse(parts[1]) ?? 0;
        return value > 0;
      });
      final needSteps = localStepsHistory.isEmpty || !hasPositiveLocalSteps;
      final needSleep = (prefs.getStringList('sleep_history') ?? []).isEmpty;
      final needWeight = (prefs.getStringList('weight_history') ?? []).isEmpty;

      if (needSteps || needSleep || needWeight) {
        final history = await fs.loadHealthHistory(365);
        if (history.isNotEmpty) {
          final stepsList = <String>[];
          final sleepList = <String>[];
          final weightList = <String>[];

          for (final day in history) {
            final date = day['date'] as String;
            
            // Steps
            if (needSteps && day['steps'] != null) {
              final steps = (day['steps'] as num).toInt();
              if (steps > 0) {
                stepsList.add('$date|$steps');
                              // Tránh reset về 0 nếu dữ liệu là của ngày hôm nay
                if (date == _todayKey()) {
                  await _persistTodaySteps(prefs, date, steps);
                }
              }
            }
            
            // Sleep
            if (needSleep && day['sleepHours'] != null) {
              final hours = (day['sleepHours'] as num).toDouble();
              if (hours > 0) sleepList.add('$date|${hours.toStringAsFixed(1)}');
            }
            
            // Weight
            if (needWeight && day['weightKg'] != null) {
              final kg = (day['weightKg'] as num).toDouble();
              if (kg > 0) weightList.add('$date|${kg.toStringAsFixed(1)}');
            }
          }

          if (stepsList.isNotEmpty) {
            // Sắp xếp theo ngày tăng dần
            stepsList.sort();
            await prefs.setStringList('steps_history', stepsList);
          }
          if (sleepList.isNotEmpty) {
            sleepList.sort();
            await prefs.setStringList('sleep_history', sleepList);
          }
          if (weightList.isNotEmpty) {
            weightList.sort();
            await prefs.setStringList('weight_history', weightList);
          }
        }
      }
    } catch (e) {
      debugPrint('Sync from Firestore error: $e');
    }
  }

  Future<void> _syncTodayStepsFromFirestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayKey = _todayKey();
      debugPrint('[_syncTodaySteps] todayKey=$todayKey, _todaySteps=$_todaySteps');

      final data = await FirestoreService().loadHealthDaily(todayKey);
      debugPrint('[_syncTodaySteps] Firestore data=$data');

      if (data == null || data['steps'] == null) {
        debugPrint('[_syncTodaySteps] No steps data on Firestore for today, skipping.');
        return;
      }

      final remoteSteps = (data['steps'] as num).toInt();
      debugPrint('[_syncTodaySteps] remoteSteps=$remoteSteps, localSteps=$_todaySteps');

      if (remoteSteps <= 0) {
        debugPrint('[_syncTodaySteps] remoteSteps <= 0, skipping.');
        return;
      }

      if (remoteSteps <= _todaySteps) {
        debugPrint('[_syncTodaySteps] remoteSteps <= _todaySteps, skipping (local is higher).');
        return;
      }

      await _persistTodaySteps(prefs, todayKey, remoteSteps);
      await _upsertStepsHistoryEntry(prefs, todayKey, remoteSteps);
      _lastSavedSteps = remoteSteps;
      debugPrint('[_syncTodaySteps] ✅ Synced steps from Firestore: $remoteSteps');
    } catch (e) {
      debugPrint('Sync today steps from Firestore error: $e');
    }
  }

  Future<void> _upsertStepsHistoryEntry(
    SharedPreferences prefs,
    String dateKey,
    int steps,
  ) async {
    final history = prefs.getStringList('steps_history') ?? [];
    history.removeWhere((e) => e.startsWith('$dateKey|'));
    history.add('$dateKey|$steps');
    while (history.length > 365) {
      history.removeAt(0);
    }
    await prefs.setStringList('steps_history', history);
  }

  Future<void> _syncLocalStepsToFirestore({int maxDays = 365}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('steps_history') ?? [];
      if (history.isEmpty) return;

      final todayKey = _todayKey();
      final lastSyncedKey = prefs.getString('steps_last_sync_date');
      String? newestSyncedKey;

      final start = history.length > maxDays ? history.length - maxDays : 0;
      for (var i = start; i < history.length; i++) {
        final parts = history[i].split('|');
        if (parts.length != 2) continue;
        final dateKey = parts[0];
        final steps = int.tryParse(parts[1]) ?? 0;
        if (lastSyncedKey != null &&
            dateKey.compareTo(lastSyncedKey) <= 0 &&
            dateKey != todayKey) {
          continue;
        }
        if (steps > 0) {
          await FirestoreService().saveHealthDaily(
            dateKey: dateKey,
            steps: steps,
          );
          if (newestSyncedKey == null ||
              dateKey.compareTo(newestSyncedKey) > 0) {
            newestSyncedKey = dateKey;
          }
        }
      }
      if (newestSyncedKey != null) {
        await prefs.setString('steps_last_sync_date', newestSyncedKey);
      }
    } catch (e) {
      debugPrint('Sync local steps to Firestore error: $e');
    }
  }

  /// Public wrapper to sync local steps to Firestore (e.g. before logout)
  Future<void> syncLocalStepsToFirestore({int maxDays = 365}) async {
    await _syncLocalStepsToFirestore(maxDays: maxDays);
  }

  /// Xin quyền ACTIVITY_RECOGNITION trên Android 10+
  Future<void> _requestActivityRecognition() async {
    try {
      await _channel.invokeMethod('requestActivityRecognition');
    } catch (e) {
      debugPrint('Activity recognition permission request error: $e');
    }
  }

  Future<bool> _isActivityRecognitionGranted() async {
    try {
      final granted = await _channel.invokeMethod<bool>('checkActivityRecognition');
      return granted ?? false;
    } catch (e) {
      debugPrint('Activity recognition permission check error: $e');
      return false;
    }
  }

  Future<bool> _ensureActivityRecognitionPermission() async {
    if (!Platform.isAndroid) return true;
    if (Platform.isAndroid && !await _isActivityRecognitionGranted()) {
      await _requestActivityRecognition();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return await _isActivityRecognitionGranted();
  }

  Future<void> _ensureHealthConfigured() async {
    if (_healthConfigured) return;
    await _health.configure();
    _healthConfigured = true;
  }

  Future<StepsRefreshResult> _getStepsFromHealth(
      {bool requestPermission = true}) async {
    if (kIsWeb) return StepsRefreshResult.noData();
    try {
      await _ensureHealthConfigured();
      final types = [HealthDataType.STEPS];
      final permissions = [HealthDataAccess.READ];

      if (Platform.isIOS) {
        // iOS đặc biệt: hasPermissions() LUÔN trả về null vì Apple không cho
        // app biết user đã cấp hay từ chối quyền (vì lý do riêng tư).
        // Chiến lược: luôn gọi requestAuthorization (iOS chỉ hiện dialog lần đầu,
        // các lần sau sẽ bỏ qua im lặng), rồi THỬ đọc dữ liệu trực tiếp.
        // Nếu đọc được → user đã cấp quyền. Nếu null → chưa cấp hoặc chưa có data.
        if (requestPermission) {
          try {
            await _health.requestAuthorization(types, permissions: permissions);
          } catch (e) {
            debugPrint('iOS requestAuthorization error (non-fatal): $e');
          }
        }
        // Luôn thử đọc dữ liệu, bất kể kết quả requestAuthorization
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final steps = await _health.getTotalStepsInInterval(start, now);
        if (steps != null) {
          return StepsRefreshResult.success(steps);
        }
        // steps == null có thể do: (1) chưa cấp quyền, hoặc (2) chưa đi bước nào
        // Thử getHealthDataFromTypes để phân biệt 2 trường hợp
        try {
          await _health.getHealthDataFromTypes(
            types: types,
            startTime: start,
            endTime: now,
          );
          // Nếu không throw exception → quyền đã được cấp, chỉ là chưa có data
          return StepsRefreshResult.success(0);
        } catch (e) {
          debugPrint('iOS health data read failed (likely no permission): $e');
          return StepsRefreshResult.permissionDenied();
        }
      } else {
        // Android: hasPermissions hoạt động bình thường
        final hasPerms = await _health.hasPermissions(
          types,
          permissions: permissions,
        );
        bool granted = hasPerms ?? false;
        if (!granted && requestPermission) {
          granted = await _health.requestAuthorization(
            types,
            permissions: permissions,
          );
        }
        if (!granted) return StepsRefreshResult.permissionDenied();
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final steps = await _health.getTotalStepsInInterval(start, now);
        if (steps == null) return StepsRefreshResult.noData();
        return StepsRefreshResult.success(steps);
      }
    } catch (e) {
      debugPrint('Health steps read error: $e');
      return StepsRefreshResult.error(e.toString());
    }
  }

  Future<void> _clearRebaseFlags(SharedPreferences prefs) async {
    await prefs.setBool('steps_need_rebase', false);
    await prefs.remove('steps_rebase_target');
    await prefs.remove('steps_rebase_date');
  }

  Future<void> _persistTodaySteps(
    SharedPreferences prefs,
    String todayKey,
    int steps,
  ) async {
    await prefs.setString('steps_date', todayKey);
    await prefs.setInt('steps_today', steps);

    if (_lastRawSteps != null) {
      await prefs.setInt('steps_baseline', _lastRawSteps! - steps);
      await _clearRebaseFlags(prefs);
    } else {
      await prefs.setBool('steps_need_rebase', true);
      await prefs.setInt('steps_rebase_target', steps);
      await prefs.setString('steps_rebase_date', todayKey);
    }

    _todaySteps = steps;
    _stepsController.add(_todaySteps);
  }

  /// Refresh steps từ HealthKit/Health Connect khi app mở lại hoặc bấm nút refresh
  Future<StepsRefreshResult> refreshStepsFromHealth({
    bool requestPermission = true,
    bool pullFromFirestore = false,
    bool saveHistory = true,
  }) async {
    final readResult =
        await _getStepsFromHealth(requestPermission: requestPermission);
    if (!readResult.isSuccess) return readResult;
    final healthSteps = readResult.steps!;

    // Also pull from Firestore to ensure latest data
    int? firestoreSteps;
    if (pullFromFirestore) {
      try {
        final todayKey = _todayKey();
        final data = await FirestoreService().loadHealthDaily(todayKey);
        if (data != null && data['steps'] != null) {
          firestoreSteps = (data['steps'] as num).toInt();
        }
      } catch (e) {
        debugPrint('Refresh: Firestore pull error: $e');
      }
    }

    // Use the maximum between Health Connect, Firestore, and local steps
    final maxLocal = healthSteps > _todaySteps ? healthSteps : _todaySteps;
    final steps = (firestoreSteps ?? 0) > maxLocal ? firestoreSteps! : maxLocal;

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    await _persistTodaySteps(prefs, todayKey, steps);
    if (saveHistory) {
      await saveTodayStepsToHistory();
    } else {
      final now = DateTime.now();
      final shouldPersistHistory = _lastHistoryPersistAt == null ||
          now.difference(_lastHistoryPersistAt!).inSeconds >=
              _historySyncInterval.inSeconds;
      if (shouldPersistHistory) {
        await saveTodayStepsToHistory();
      }
    }
    return StepsRefreshResult.success(steps);
  }

  void _startListening() {
    try {
      _stepSubscription?.cancel();
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );
      _startPeriodicReconcile();
    } catch (e) {
      debugPrint('Pedometer init error: $e');
    }
  }

  void _startPeriodicReconcile() {
    _reconcileTimer?.cancel();
    // Tạm thời vô hiệu hóa vòng lặp gọi Apple Health/Google Fit mỗi 1 giây ngầm.
    // Việc này giúp tránh xung đột dữ liệu với cảm biến Pedometer (gây khựng bước chân)
    // và tiết kiệm lượng lớn pin cho người dùng.
    // Dữ liệu sẽ chỉ đồng bộ với Health/Fit khi: 
    // 1. Mở app lên (initState/init)
    // 2. Chuyển từ chạy nền lên màn hình (resume)
    // 3. User tự bấm nút làm mới.
  }

  void _onStepCount(StepCount event) async {
    if (!_legacySensorCountingEnabled) {
      _lastRawSteps = event.steps;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final savedDate = prefs.getString('steps_date') ?? '';
    _lastRawSteps = event.steps;

    final needRebase = prefs.getBool('steps_need_rebase') ?? false;
    final rebaseTarget = prefs.getInt('steps_rebase_target');
    final rebaseDate = prefs.getString('steps_rebase_date');

    if (savedDate != todayKey) {
      // Ngày mới → lưu lại steps ngày hôm qua trước khi reset
      if (savedDate.isNotEmpty && _todaySteps > 0) {
        await saveTodayStepsToHistory();
      }
      // Reset baseline cho ngày mới
      await prefs.setString('steps_date', todayKey);
      await prefs.setInt('steps_baseline', event.steps);
      _todaySteps = 0;
      _lastSavedSteps = null;
      await _clearRebaseFlags(prefs);
    } else {
      if (needRebase && rebaseTarget != null && rebaseDate == todayKey) {
        final baseline = event.steps - rebaseTarget;
        await prefs.setInt('steps_baseline', baseline);
        _todaySteps = rebaseTarget;
        await _clearRebaseFlags(prefs);
      } else {
        var baseline = prefs.getInt('steps_baseline');
        if (baseline == null) {
          // If baseline is missing, infer from current displayed steps to avoid getting stuck at 0.
          baseline = (event.steps - _todaySteps).clamp(0, event.steps);
          await prefs.setInt('steps_baseline', baseline);
        }
        _todaySteps = event.steps - baseline;
        if (_todaySteps < 0) _todaySteps = 0;
      }
    }

    await prefs.setInt('steps_today', _todaySteps);
    _stepsController.add(_todaySteps);

    // Lưu lịch sử + sync Firestore khi steps thay đổi
    _debouncedSave();
  }

  void _onStepCountError(dynamic error) {
    debugPrint('Step count error: $error');
  }

  /// Lưu history + Firestore khi steps thay đổi
  void _debouncedSave() {
    if (_lastSavedSteps != null && _todaySteps == _lastSavedSteps) {
      return;
    }
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 1), () async {
      try {
        await saveTodayStepsToHistory();
      } catch (e) {
        debugPrint('Debounced step save error: $e');
      }
    });
  }

  Future<void> _loadTodaySteps() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('steps_date') ?? '';
    if (savedDate == _todayKey()) {
      _todaySteps = prefs.getInt('steps_today') ?? 0;
    } else {
      _todaySteps = 0;
    }
    _lastSavedSteps = _todaySteps;
    _stepsController.add(_todaySteps);
  }

  /// Cộng bước theo quãng đường thực tế khi user đang bật phiên hoạt động.
  /// Dùng cho cơ chế mới: chỉ tăng bước khi đang tracking và có di chuyển thật.
  Future<int> addStepsFromTrackedDistance({
    required double distanceMeters,
    double strideMeters = 0.762,
  }) async {
    if (distanceMeters <= 0 || strideMeters <= 0) return _todaySteps;

    _pendingDistanceMetersForSteps += distanceMeters;
    final stepsDelta = (_pendingDistanceMetersForSteps / strideMeters).floor();
    if (stepsDelta <= 0) return _todaySteps;
    _pendingDistanceMetersForSteps -= stepsDelta * strideMeters;

    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final savedDate = prefs.getString('steps_date') ?? '';

    if (savedDate != todayKey) {
      if (savedDate.isNotEmpty && _todaySteps > 0) {
        await saveTodayStepsToHistory();
      }
      _todaySteps = 0;
      _lastSavedSteps = 0;
      await prefs.setString('steps_date', todayKey);
    }

    _todaySteps += stepsDelta;
    await prefs.setInt('steps_today', _todaySteps);

    if (_lastRawSteps != null) {
      final inferredBaseline = (_lastRawSteps! - _todaySteps).clamp(0, _lastRawSteps!);
      await prefs.setInt('steps_baseline', inferredBaseline);
      await _clearRebaseFlags(prefs);
    } else {
      await prefs.setBool('steps_need_rebase', true);
      await prefs.setInt('steps_rebase_target', _todaySteps);
      await prefs.setString('steps_rebase_date', todayKey);
    }

    _stepsController.add(_todaySteps);
    _debouncedSave();
    return _todaySteps;
  }

  Future<void> saveActivitySession({
    required String mode,
    required DateTime startedAt,
    required DateTime endedAt,
    required double distanceMeters,
    required int stepsDelta,
    double? avgSpeedMps,
    String source = 'gps_tracking',
    List<Map<String, dynamic>>? segments,
    String? sessionId,
    bool upsert = false,
  }) async {
    if (distanceMeters <= 0 && stepsDelta <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final sessions = prefs.getStringList('activity_sessions') ?? [];

    final safeEndedAt = endedAt.isBefore(startedAt) ? startedAt : endedAt;
    final durationSec = safeEndedAt.difference(startedAt).inSeconds;

    final id = sessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final payload = <String, dynamic>{
      'id': id,
      'mode': mode,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': safeEndedAt.toIso8601String(),
      'durationSec': durationSec,
      'distanceMeters': distanceMeters,
      'stepsDelta': stepsDelta,
      'avgSpeedMps': avgSpeedMps ?? 0,
      'source': source,
    };
    if (segments != null && segments.isNotEmpty) {
      payload['segments'] = segments;
    }

    if (upsert) {
      final index = sessions.indexWhere((row) {
        try {
          final decoded = jsonDecode(row);
          return decoded is Map<String, dynamic> && decoded['id'] == id;
        } catch (_) {
          return false;
        }
      });
      if (index >= 0) {
        sessions[index] = jsonEncode(payload);
      } else {
        sessions.add(jsonEncode(payload));
      }
    } else {
      sessions.add(jsonEncode(payload));
    }
    while (sessions.length > 200) {
      sessions.removeAt(0);
    }
    await prefs.setStringList('activity_sessions', sessions);
    await _syncTodayActivityBreakdownToFirestore();
  }

  Future<void> _syncTodayActivityBreakdownToFirestore() async {
    final sessions = await getActivitySessions(limit: 200);
    final todayKey = _todayKey();

    double walkMeters = 0;
    double runMeters = 0;
    double bikeMeters = 0;

    for (final item in sessions) {
      final endedAtRaw = (item['endedAt'] ?? '').toString();
      final endedAt = DateTime.tryParse(endedAtRaw);
      if (endedAt == null || _dateKeyFromDate(endedAt) != todayKey) {
        continue;
      }

      final segments = item['segments'];
      if (segments is List) {
        for (final raw in segments) {
          if (raw is! Map) continue;
          final mode = (raw['mode'] ?? '').toString().toLowerCase();
          final meters = (raw['distanceMeters'] as num?)?.toDouble() ?? 0;
          if (meters <= 0) continue;
          if (mode == 'walk') walkMeters += meters;
          if (mode == 'run' || mode == 'running') runMeters += meters;
          if (mode == 'bike') bikeMeters += meters;
        }
      } else {
        final mode = (item['mode'] ?? '').toString().toLowerCase();
        final meters = (item['distanceMeters'] as num?)?.toDouble() ?? 0;
        if (meters <= 0) continue;
        if (mode == 'walk') walkMeters += meters;
        if (mode == 'run' || mode == 'running') runMeters += meters;
        if (mode == 'bike') bikeMeters += meters;
      }
    }

    final totalMeters = walkMeters + runMeters + bikeMeters;
    double toKm(double meters) => double.parse((meters / 1000).toStringAsFixed(3));
    await FirestoreService().saveHealthDaily(
      dateKey: todayKey,
      activityBreakdown: {
        'walkKm': toKm(walkMeters),
        'runKm': toKm(runMeters),
        'bikeKm': toKm(bikeMeters),
        'totalKm': toKm(totalMeters),
      },
    );
  }

  String _dateKeyFromDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, dynamic>>> getActivitySessions({int limit = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = prefs.getStringList('activity_sessions') ?? [];
    final result = <Map<String, dynamic>>[];

    for (final row in sessions.reversed) {
      try {
        final map = jsonDecode(row);
        if (map is Map<String, dynamic>) {
          result.add(map);
        }
      } catch (_) {
        // Skip malformed rows.
      }
      if (result.length >= limit) break;
    }

    return result;
  }

  /// Khoảng cách (km) từ số bước chân (avg stride 0.762m)
  double getDistanceKm(int steps) => steps * 0.000762;

  /// Khoảng cách (m) từ số bước chân
  double getDistanceM(int steps) => steps * 0.762;

  /// Format khoảng cách: dưới 1km → hiện m, từ 1km → hiện km
  String formatDistance(int steps) {
    final meters = getDistanceM(steps);
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Calories từ số bước chân (avg 0.04 kcal/step)
  double getCalories(int steps) => steps * 0.04;

  // ===== STEP HISTORY =====

  Future<List<Map<String, dynamic>>> getStepHistory({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('steps_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({'date': parts[0], 'steps': int.tryParse(parts[1]) ?? 0});
      }
      if (result.length >= days) break;
    }
    return result;
  }

  /// Lưu steps cuối ngày vào history (gọi khi app resume hoặc midnight)
  Future<void> saveTodayStepsToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('steps_history') ?? [];

    // Xóa entry cũ của hôm nay (nếu có)
    int? existingSteps;
    for (var i = 0; i < history.length; i++) {
      if (history[i].startsWith('$todayKey|')) {
        final parts = history[i].split('|');
        if (parts.length == 2) {
          existingSteps = int.tryParse(parts[1]);
        }
        history.removeAt(i);
        break;
      }
    }

    final stepsToSave =
        (_todaySteps <= 0 && (existingSteps ?? 0) > 0) ? existingSteps! : _todaySteps;
    history.add('$todayKey|$stepsToSave');

    // Giữ 365 ngày
    while (history.length > 365) {
      history.removeAt(0);
    }
    await prefs.setStringList('steps_history', history);

    // Sync to Firestore
    if (stepsToSave > 0) {
      await FirestoreService().saveHealthDaily(
        dateKey: todayKey,
        steps: stepsToSave,
      );
    }
    _lastHistoryPersistAt = DateTime.now();
    _lastSavedSteps = stepsToSave;
  }

  // ===== HEIGHT & BMI =====

  Future<void> saveHeight(double cm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_height_cm', cm);

    // Sync to Firestore
    await FirestoreService().saveHealthDaily(dateKey: _todayKey(), heightCm: cm);
  }

  Future<double?> getHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('user_height_cm')
        ? prefs.getDouble('user_height_cm')
        : null;
  }

  /// Tính BMI = weight(kg) / height(m)²
  double? calculateBMI(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// Phân loại BMI
  String bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Thiếu cân';
    if (bmi < 24.9) return 'Bình thường';
    if (bmi < 30) return 'Thừa cân';
    return 'Béo phì';
  }

  /// Màu cho BMI
  String bmiStatus(double bmi) {
    if (bmi < 18.5) return 'warning';
    if (bmi < 24.9) return 'good';
    if (bmi < 30) return 'warning';
    return 'bad';
  }

  // ===== SLEEP ASSESSMENT =====

  /// Đánh giá giấc ngủ (người lớn 7-9h)
  String sleepAssessment(double? hours) {
    if (hours == null) return '';
    if (hours >= 7 && hours <= 9) return 'good';
    if (hours >= 6 && hours < 7) return 'warning';
    return 'bad';
  }

  String sleepLabel(double? hours) {
    if (hours == null) return '';
    if (hours >= 7 && hours <= 9) return 'Tốt ✅';
    if (hours >= 6 && hours < 7) return 'Hơi thiếu ⚠️';
    if (hours > 9) return 'Ngủ quá nhiều ⚠️';
    return 'Thiếu ngủ ❌';
  }

  // ===== HEALTH RECOMMENDATIONS =====

  List<String> getRecommendations({
    double? sleepHours,
    double? weightKg,
    double? heightCm,
    int steps = 0,
  }) {
    final tips = <String>[];
    final bmi = calculateBMI(weightKg, heightCm);
    final dayOfWeek = DateTime.now().weekday;

    // Daily rotating healthy menu
    const dailyMenus = {
      1: 'Thực đơn lành mạnh hôm nay: Ưu tiên đạm từ cá và rau xanh lá đậm. Bắt đầu tuần mới bằng 15 phút thiền hoặc giãn cơ buổi sáng.',
      2: 'Thực đơn lành mạnh hôm nay: Bổ sung ngũ cốc nguyên hạt và trái cây mọng nước. Thử thay thang máy bằng thang bộ trong ngày.',
      3: 'Thực đơn lành mạnh hôm nay: Nạp năng lượng với các loại hạt và sữa chua không đường. Uống đủ 2 lít nước để tăng trao đổi chất.',
      4: 'Thực đơn lành mạnh hôm nay: Tập trung vào chất béo lành mạnh (bơ, dầu olive) và thịt trắng. Đi bộ nhẹ nhàng sau bữa tối.',
      5: 'Thực đơn lành mạnh hôm nay: Giảm muối và đường tinh luyện. Thưởng thức nước ép quả tươi để bổ sung vitamin C cuối tuần.',
      6: 'Thực đơn lành mạnh hôm nay: Ngày thanh lọc với nhiều rau củ quả. Dành 30 phút cho hoạt động thể thao ngoài trời.',
      7: 'Thực đơn lành mạnh hôm nay: Bữa sáng giàu dinh dưỡng và thư giãn tinh thần. Tắt thiết bị điện tử sớm để chuẩn bị giấc ngủ sâu.',
    };
    tips.add(dailyMenus[dayOfWeek]!);

    // Sleep advice
    if (sleepHours != null) {
      if (sleepHours < 6) {
        tips.add('Thiếu ngủ: Nên duy trì giấc ngủ 7-8 giờ/đêm để phục hồi cơ bắp và thần kinh.');
      } else if (sleepHours > 9) {
        tips.add('Hội chứng ngủ nhiều: Hãy thử ngủ 7-8 giờ và dậy sớm tập thể dục.');
      }
    }

    // BMI advice
    if (bmi != null) {
      if (bmi < 18.5) {
        final idealWeight = 18.5 * (heightCm! / 100) * (heightCm / 100);
        final needKg = idealWeight - weightKg!;
        tips.add('Chế độ dinh dưỡng: Khuyến nghị tăng ~${needKg.toStringAsFixed(1)} kg. Ăn 5-6 bữa nhỏ/ngày, bổ sung protein và carb lành mạnh.');
      } else if (bmi >= 25 && bmi < 30) {
        final idealWeight = 24.9 * (heightCm! / 100) * (heightCm / 100);
        final loseKg = weightKg! - idealWeight;
        tips.add('Kiểm soát calo: Khuyến nghị giảm ~${loseKg.toStringAsFixed(1)} kg. Hạn chế đồ ngọt/chiên xào và ưu tiên chất xơ tươi.');
      } else if (bmi >= 30) {
        tips.add('Chế độ ăn kiêng: Thể trạng béo phì. Cần thiết lập chế độ giảm calo nghiêm ngặt và theo dõi y tế.');
      }
    }

    // Steps advice
    if (steps < 5000) {
      tips.add('Vận động: Hôm nay cường độ di chuyển thấp ($steps bước). Hãy đứng dậy đi lại mỗi 1 tiếng làm việc.');
    } else if (steps >= 10000) {
      tips.add('Thành tích: Bạn đã vượt mốc 10,000 bước xuất sắc trong hôm nay.');
    }

    return tips;
  }

  // ===== SLEEP TRACKING =====

  Future<void> saveSleepHours(double hours) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('sleep_history') ?? [];

    history.removeWhere((e) => e.startsWith('$todayKey|'));
    history.add('$todayKey|${hours.toStringAsFixed(1)}');

    while (history.length > 30) {
      history.removeAt(0);
    }
    await prefs.setStringList('sleep_history', history);

    // Sync to Firestore
    await FirestoreService().saveHealthDaily(dateKey: todayKey, sleepHours: hours);
  }

  Future<double?> getTodaySleep() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sleep_history') ?? [];
    final todayKey = _todayKey();
    for (final entry in history.reversed) {
      if (entry.startsWith('$todayKey|')) {
        return double.tryParse(entry.split('|')[1]);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getSleepHistory({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sleep_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({
          'date': parts[0],
          'hours': double.tryParse(parts[1]) ?? 0,
        });
      }
      if (result.length >= days) break;
    }
    return result;
  }

  // ===== WEIGHT TRACKING =====

  Future<void> saveWeight(double kg) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('weight_history') ?? [];

    history.removeWhere((e) => e.startsWith('$todayKey|'));
    history.add('$todayKey|${kg.toStringAsFixed(1)}');

    while (history.length > 90) {
      history.removeAt(0);
    }
    await prefs.setStringList('weight_history', history);

    // Sync to Firestore
    await FirestoreService().saveHealthDaily(dateKey: todayKey, weightKg: kg);
  }

  Future<double?> getLatestWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('weight_history') ?? [];
    if (history.isEmpty) return null;
    final parts = history.last.split('|');
    return parts.length == 2 ? double.tryParse(parts[1]) : null;
  }

  Future<List<Map<String, dynamic>>> getWeightHistory({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('weight_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({
          'date': parts[0],
          'weight': double.tryParse(parts[1]) ?? 0,
        });
      }
      if (result.length >= days) break;
    }
    return result;
  }

  // ===== BIRTHDAY =====

  Future<List<Map<String, String>>> getBirthdays() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    return list.map((e) {
      final parts = e.split('|');
      return {
        'name': parts[0],
        'date': parts.length > 1 ? parts[1] : '',
      };
    }).toList();
  }

  Future<void> addBirthday(String name, String date) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    list.add('$name|$date');
    await prefs.setStringList('birthdays', list);

    // Sync to Firestore
    final allBirthdays = await getBirthdays();
    FirestoreService().saveBirthdays(allBirthdays);
  }

  Future<void> removeBirthday(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList('birthdays', list);

      // Sync to Firestore
      final allBirthdays = await getBirthdays();
      FirestoreService().saveBirthdays(allBirthdays);
    }
  }

  /// Lấy danh sách tên sinh nhật hôm nay (dd/MM)
  Future<List<String>> getTodayBirthdays() async {
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
    final birthdays = await getBirthdays();
    return birthdays
        .where((b) => b['date'] == today)
        .map((b) => b['name']!)
        .toList();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _stepSubscription?.cancel();
    _stepsController.close();
  }
}
