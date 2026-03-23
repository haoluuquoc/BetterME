import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/notification_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';
import '../../services/auth_service.dart';
import 'water_alarm_screen.dart';
import 'update_alarm_screen.dart';
import 'settings_screen.dart';
import 'health_screen.dart';
import '../widgets/water_glass_widget.dart';
import '../widgets/glass_card.dart';
import '../widgets/rain_background.dart';
import '../widgets/coin_background.dart';
import '../widgets/heartbeat_background.dart';

/// Home Screen - Màn hình chính
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {0};
  StreamSubscription<String?>? _notificationSubscription;
  StreamSubscription<void>? _alarmSubscription;
  StreamSubscription<void>? _updateAlarmSubscription;
  bool _isAlarmShowing = false;
  DateTime? _lastAlarmDismissed;
  final _waterReminderKey = GlobalKey<_WaterReminderScreenState>();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotificationListener();
    _setupAlarmListener();
    _setupUpdateAlarmListener();
    _checkPendingNotification();
    _checkNavigateToTab();
    // Kiểm tra cập nhật khi mở app
    if (!kIsWeb && Platform.isAndroid) {
      _checkForAppUpdate();
    }
  }
  
  /// Kiểm tra flag navigate_to_tab (từ "Uống ngay" trên alarm screen khi launch từ notification)
  void _checkNavigateToTab() async {
    final prefs = await SharedPreferences.getInstance();
    final tabIndex = prefs.getInt('navigate_to_tab');
    if (tabIndex != null) {
      await prefs.remove('navigate_to_tab');
      if (mounted) {
        _openTab(tabIndex);
      }
    }
  }

  void _openTab(int index) {
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _alarmSubscription?.cancel();
    _updateAlarmSubscription?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Flush steps before app goes to background
      HealthService().saveTodayStepsToHistory();
      HealthService().syncLocalStepsToFirestore();
    }
    if (state == AppLifecycleState.resumed) {
      // Không check nếu vừa dismiss alarm screen trong 2 giây gần đây
      if (_lastAlarmDismissed != null) {
        final diff = DateTime.now().difference(_lastAlarmDismissed!);
        if (diff.inSeconds < 2) return;
      }
      // App vừa quay lại foreground → kiểm tra có pending alarm không
      _checkPendingNotification();
      
      // iOS: kiểm tra notification đã fire trong lúc ở background
      // Và reschedule thêm notifications (iOS giới hạn 64 pending)
      if (!kIsWeb && Platform.isIOS) {
        _checkIOSAlarmAndReschedule();
      }
    }
  }
  
  /// iOS: reschedule notifications khi app resumed (iOS giới hạn 64 pending)
  /// Hiện popup nhẹ thay vì alarm screen toàn màn hình
  void _checkIOSAlarmAndReschedule() async {
    // Reschedule để luôn có đủ notifications cho tương lai
    NotificationService().rescheduleWaterReminder();
    
    // Kiểm tra xem có alarm đã fire chưa xử lý không → hiện popup
    final shouldShowAlarm = await NotificationService().checkIOSPendingAlarm();
    if (shouldShowAlarm && mounted && !_isAlarmShowing) {
      _showWaterReminderPopup();
    }
  }
  
  /// Listener: nhận signal từ IsolateNameServer khi app đang mở
  void _setupAlarmListener() {
    if (kIsWeb) return;
    _alarmSubscription = NotificationService.onAlarmFired.listen((_) async {
      if (!kIsWeb && Platform.isIOS) {
        return;
      }
      // Reset block flag khi có alarm mới (dùng SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('block_alarm_screen', false);
      
      if (mounted && !_isAlarmShowing) {
        // Check nếu là snooze (từ snooze callback)
        final wasSnooze = prefs.getBool('water_snooze_just_fired') ?? false;
        await prefs.setBool('water_snooze_just_fired', false);
        _showAlarmScreen(isSnooze: wasSnooze);
      }
    });
  }
  
  /// Listener: nhận signal update alarm
  void _setupUpdateAlarmListener() {
    if (kIsWeb) return;
    _updateAlarmSubscription = NotificationService.onUpdateAlarmFired.listen((_) {
      if (!kIsWeb && Platform.isIOS) {
        return;
      }
      if (mounted) {
        _showUpdateAlarmScreen();
      }
    });
  }
  
  /// Hiện UpdateAlarmScreen full-screen kiểu báo thức
  void _showUpdateAlarmScreen() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const UpdateAlarmScreen(),
      ),
    );
    
    if (result == 'update') {
      // Chuyển sang tab Settings (index 4 vì thêm tab Sức khỏe)
      _openTab(4);
    }
  }
  
  /// Hiện WaterAlarmScreen full-screen kiểu báo thức
  void _showAlarmScreen({bool isSnooze = false}) async {
    if (_isAlarmShowing) return;
    
    // Check block flag từ SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final blocked = prefs.getBool('block_alarm_screen') ?? false;
    if (blocked) return;
    
    _isAlarmShowing = true;
    
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WaterAlarmScreen(isSnooze: isSnooze),
      ),
    );
    
    _isAlarmShowing = false;
    _lastAlarmDismissed = DateTime.now();
    
    if (result == 'drink') {
      _openTab(1);
      _checkGoalAndAskContinue();
    }
    // result == 'snooze' → đã xử lý trong WaterAlarmScreen
  }
  
  /// Popup nhẹ thay thế alarm screen trên iOS
  /// Hiện dialog nhỏ với "Uống ngay" / "Để sau" thay vì toàn màn hình vàng đen
  void _showWaterReminderPopup() async {
    if (_isAlarmShowing || !mounted) return;
    _isAlarmShowing = true;
    
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text('💧', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            const Text('Nhắc nhở uống nước'),
          ],
        ),
        content: const Text(
          'Đã đến lúc uống nước rồi! 🥤\nHãy uống một cốc nước để giữ sức khỏe nhé.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'snooze'),
            child: const Text('Để sau'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'drink'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Uống ngay'),
          ),
        ],
      ),
    );
    
    _isAlarmShowing = false;
    _lastAlarmDismissed = DateTime.now();
    
    if (result == 'drink') {
      NotificationService().cancelNotification(0);
      NotificationService().cancelSnooze();
      _openTab(1);
      _checkGoalAndAskContinue();
    } else if (result == 'snooze') {
      NotificationService().cancelNotification(0);
      NotificationService().scheduleSnooze();
    }
  }
  
  /// Kiểm tra mục tiêu và hỏi người dùng có muốn tiếp tục nhắc không
  void _checkGoalAndAskContinue() async {
    final prefs = await SharedPreferences.getInstance();
    final currentMl = prefs.getInt('water_current_ml') ?? 0;
    final goalMl = prefs.getInt('water_daily_goal_ml') ?? 2000;
    
    if (currentMl >= goalMl) {
      // Đã đạt mục tiêu → hỏi có muốn tiếp tục nhắc không
      if (!mounted) return;
      final continueReminder = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Đã đủ mục tiêu!'),
          content: Text(
            'Bạn đã uống đủ ${goalMl}ml hôm nay.\n'
            'Bạn có muốn tiếp tục nhận nhắc nhở không?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Không, tắt nhắc nhở'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Tiếp tục nhắc'),
            ),
          ],
        ),
      );
      
      if (continueReminder == false) {
        // Tự tắt reminder
        await NotificationService().stopWaterReminder();
        await prefs.setBool('water_reminder_enabled', false);
        // Sync toggle trên WaterReminderScreen
        _waterReminderKey.currentState?._loadReminderSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tắt nhắc nhở uống nước')),
          );
        }
      }
    }
  }
  
  // ====== AUTO UPDATE CHECK ======
  int _currentBuildNumber = 1;
  String _currentVersion = '1.0.0';

  void _checkForAppUpdate() async {
    // Đọc version thật từ package info
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuildNumber = int.tryParse(info.buildNumber) ?? 1;
    } catch (_) {}

    // Chỉ check 1 lần mỗi 24h
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt('last_update_check_ms') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastCheck < 86400000) return; // 24h
    await prefs.setInt('last_update_check_ms', now);

    try {
      final updateInfo = await FirestoreService().checkForUpdate();
      if (updateInfo == null) return;

      final serverBuild = updateInfo['buildNumber'] as int? ?? 0;
      final serverVersion = updateInfo['version'] as String? ?? '';
      final downloadUrl = updateInfo['downloadUrl'] as String? ?? '';
      final notes = updateInfo['notes'] as String? ?? '';
      final requiredCode = updateInfo['code'] as String? ?? '';

      if (serverBuild <= _currentBuildNumber || downloadUrl.isEmpty) return;

      if (!mounted) return;
      // Hiện dialog cập nhật
      _showAppUpdateDialog(serverVersion, notes, downloadUrl, requiredCode);
    } catch (e) {
      debugPrint('Auto update check error: $e');
    }
  }

  void _showAppUpdateDialog(String newVersion, String notes, String downloadUrl, String requiredCode) {
    final codeController = TextEditingController();
    final needCode = requiredCode.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text('Có phiên bản mới $newVersion')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bạn đang dùng: $_currentVersion',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(notes, style: const TextStyle(fontSize: 13)),
                ),
              ],
              if (needCode) ...[
                const SizedBox(height: 14),
                const Text('Nhập mã cập nhật:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Nhập mã...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Lên lịch nhắc nhở cập nhật sau 20 giây (màn hình vàng đen)
              NotificationService().scheduleUpdateAlarm(
                version: newVersion,
                notes: notes,
                downloadUrl: downloadUrl,
              );
            },
            child: const Text('Để sau'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Cập nhật ngay'),
            onPressed: () {
              if (needCode) {
                final entered = codeController.text.trim().toUpperCase();
                if (entered != requiredCode.toUpperCase()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mã không đúng')),
                  );
                  return;
                }
              }
              Navigator.pop(ctx);
              _downloadAndInstallUpdate(downloadUrl);
            },
          ),
        ],
      ),
    );
  }

  void _downloadAndInstallUpdate(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('Đang tải bản cập nhật...\n${uri.host}')),
            ],
          ),
        ),
      ),
    );

    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải: HTTP ${response.statusCode}')),
          );
        }
        return;
      }

      final tempDir = await Directory.systemTemp;
      final file = File('${tempDir.path}/betterme_update.apk');
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      httpClient.close();

      if (mounted) Navigator.pop(context);

      final installed = await NotificationService().installApk(file.path);
      if (!installed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cài đặt. Kiểm tra quyền.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  void _setupNotificationListener() {
    if (kIsWeb) return;
    
    _notificationSubscription = NotificationService.onNotificationTap.listen((payload) {
      if (payload == 'water_drink_tab') {
        // Nếu alarm screen đang hiện → đóng nó
        if (_isAlarmShowing && mounted) {
          Navigator.of(context).pop('drink');
        }
        _openTab(1);
        NotificationService().cancelSnooze();
        _checkGoalAndAskContinue();
      }
    });
  }
  
  void _checkPendingNotification() async {
    if (kIsWeb) return;
    
    final payload = NotificationService.pendingPayload;
    NotificationService.pendingPayload = null;
    
    if (payload == 'water_drink_tab') {
      // User bấm "Uống ngay" từ notification → vào tab uống nước
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        NotificationService().cancelSnooze();
        _openTab(1);
      });
    } else if (payload == 'water_alarm_screen') {
      if (!kIsWeb && Platform.isIOS) {
        // iOS: hiện popup thay vì alarm screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().cancelNotification(0);
          _showWaterReminderPopup();
        });
        return;
      }
      // Android: alarm screen toàn màn hình
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        _showAlarmScreen();
      });
    } else if (payload == 'water_snooze') {
      if (!kIsWeb && Platform.isIOS) {
        // iOS: schedule snooze trực tiếp, không cần alarm screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().cancelNotification(0);
          NotificationService().scheduleSnooze();
        });
        return;
      }
      // Android: xử lý snooze từ notification khi app chưa chạy
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        NotificationService().scheduleSnooze();
        NotificationService().showSimpleNotification(
          title: 'Nhắc nhở uống nước',
          body: 'Sẽ nhắc lại sau 20 giây',
          payload: 'water_reminder',
        );
      });
    } else {
      // Kiểm tra pending alarm từ background
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      
      // Check block flag
      final blocked = prefs.getBool('block_alarm_screen') ?? false;
      if (blocked) return;
      
      final pending = prefs.getBool('pending_water_dialog') ?? false;
      if (pending && mounted) {
        await prefs.setBool('pending_water_dialog', false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().cancelNotification(0);
          if (!kIsWeb && Platform.isIOS) {
            _showWaterReminderPopup();
          } else {
            _showAlarmScreen();
          }
        });
      }
    }
  }

  Widget _buildTabIfVisited(int index, Widget child) {
    if (_visitedTabs.contains(index) || _currentIndex == index) {
      return child;
    }
    return const SizedBox.shrink();
  }

  Widget _buildDynamicBackground(Widget child) {
    switch (_currentIndex) {
      case 2: // Chi tiêu
        return CoinBackground(child: child);
      case 3: // Sức khỏe
        return HeartbeatBackground(child: child);
      case 0:
      case 1:
      case 4:
      default:
        return RainBackground(child: child);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildDynamicBackground(
      Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildTabIfVisited(0, HomeContent(onNavigate: _openTab)),
            _buildTabIfVisited(1, WaterReminderScreen(key: _waterReminderKey)),
            _buildTabIfVisited(2, const ExpenseScreen()),
            _buildTabIfVisited(3, const HealthScreen()),
            _buildTabIfVisited(4, const SettingsContent()),
          ],
        ),
        bottomNavigationBar: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 70),
          child: Theme(
            data: ThemeData(
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: Colors.white.withOpacity(0.03),
                indicatorColor: Colors.white.withOpacity(0.2),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                labelTextStyle: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold);
                  }
                  return const TextStyle(color: Colors.white70, fontSize: 11);
                }),
              ),
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _openTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined, color: Colors.white70, size: 24),
                      selectedIcon: Icon(Icons.home, color: Colors.white, size: 24),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.water_drop_outlined, color: Colors.white70, size: 24),
                      selectedIcon: Icon(Icons.water_drop, color: Colors.white, size: 24),
                      label: 'Water',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 24),
                      selectedIcon: Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
                      label: 'Expense',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.favorite_outline, color: Colors.white70, size: 24),
                      selectedIcon: Icon(Icons.favorite, color: Colors.white, size: 24),
                      label: 'Health',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined, color: Colors.white70, size: 24),
                      selectedIcon: Icon(Icons.settings, color: Colors.white, size: 24),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Home Content - Trang chủ tổng quan
class HomeContent extends StatefulWidget {
  final void Function(int)? onNavigate;
  const HomeContent({super.key, this.onNavigate});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with WidgetsBindingObserver {
  int _waterCurrentMl = 0;
  int _waterGoalMl = 2000;
  double _totalIncome = 0;
  double _totalExpense = 0;
  String _profileName = 'bạn';

  // Health data
  int _todaySteps = 0;
  double? _todaySleep;
  double? _latestWeight;
  List<String> _todayBirthdays = [];
  StreamSubscription<int>? _stepsSub;
  final _healthService = HealthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _initHealth();
  }

  Future<void> _initHealth() async {
    await _healthService.init();
    _todaySteps = _healthService.todaySteps;
    await _stepsSub?.cancel();
    _stepsSub = _healthService.stepsStream.listen((steps) {
      if (mounted) setState(() => _todaySteps = steps);
    });
    final sleep = await _healthService.getTodaySleep();
    final weight = await _healthService.getLatestWeight();
    final bdays = await _healthService.getTodayBirthdays();
    if (mounted) {
      setState(() {
        _todaySleep = sleep;
        _latestWeight = weight;
        _todayBirthdays = bdays;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepsSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initHealth();
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    
    // Water data
    final todayKey = _todayKey();
    final lastDate = prefs.getString('water_last_date') ?? '';
    int currentMl = 0;
    if (lastDate == todayKey) {
      currentMl = prefs.getInt('water_current_ml') ?? 0;
    }
    final goalMl = prefs.getInt('water_daily_goal_ml') ?? 2000;

    // Expense data - parse transactions
    final data = prefs.getStringList('expense_transactions') ?? [];
    double income = 0;
    double expense = 0;
    for (final entry in data) {
      final parts = entry.split('|');
      if (parts.length >= 5) {
        final type = parts[0];
        final amount = double.tryParse(parts[1]) ?? 0.0;
        if (type == 'income') {
          income += amount;
        } else {
          expense += amount;
        }
      }
    }
    
    final user = AuthService().currentUser;
    final pName = user?.displayName ?? prefs.getString('profile_name') ?? 'bạn';

    if (mounted) {
      setState(() {
        _waterCurrentMl = currentMl;
        _waterGoalMl = goalMl;
        _totalIncome = income;
        _totalExpense = expense;
        _profileName = pName;
      });
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}k';
    }
    return '${amount.toStringAsFixed(0)}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('BetterME', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới dữ liệu',
            onPressed: () async {
              await _loadData();
              await _initHealth();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã làm mới dữ liệu'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreetingSection(context),
              // Birthday banner
              if (_todayBirthdays.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildBirthdayBanner(context),
              ],
              const SizedBox(height: 20),
              // Daily Health Dashboard
              _buildDailyDashboard(context),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => widget.onNavigate?.call(1),
                child: _buildWaterSummaryCard(context),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => widget.onNavigate?.call(2),
                child: _buildExpenseSummaryCard(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingSection(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    String emoji;
    
    if (hour >= 5 && hour < 12) {
      greeting = 'Chào buổi sáng!';
      emoji = '☀️';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Chào buổi chiều!';
      emoji = '🌤️';
    } else if (hour >= 18 && hour < 22) {
      greeting = 'Chào buổi tối!';
      emoji = '🌙';
    } else {
      greeting = 'Khuya rồi!';
      emoji = '🌃';
    }

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Hi $_profileName,\nThế nào rồi?',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '$greeting Chăm sóc sức khỏe & tài chính nhé!',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayBanner(BuildContext context) {
    final names = _todayBirthdays.join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.pink.shade50, Colors.orange.shade50],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Row(
        children: [
          const Text('🎂', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Hôm nay là sinh nhật $names 🎉',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.pink.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyDashboard(BuildContext context) {
    final theme = Theme.of(context);
    final glasses = (_waterCurrentMl / 250).floor();
    final balance = _totalIncome - _totalExpense;

    return GestureDetector(
      onTap: () => widget.onNavigate?.call(3), // Sức khỏe tab
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.dashboard,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Tổng quan hôm nay',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
            const SizedBox(height: 20),
            // 2x2 Grid
            Row(
              children: [
                Expanded(
                  child: _buildDashboardItem(
                    theme,
                    Icons.directions_walk,
                    '$_todaySteps',
                    'Bước chân',
                    Colors.orangeAccent,
                  ),
                ),
                Expanded(
                  child: _buildDashboardItem(
                    theme,
                    Icons.water_drop,
                    '$glasses ly',
                    'Nước uống',
                    Colors.lightBlueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDashboardItem(
                    theme,
                    Icons.bedtime,
                    _todaySleep != null
                        ? '${_todaySleep!.toStringAsFixed(1)}h'
                        : '--',
                    'Giấc ngủ',
                    Colors.indigoAccent,
                  ),
                ),
                Expanded(
                  child: _buildDashboardItem(
                    theme,
                    Icons.account_balance_wallet,
                    _formatCurrency(balance < 0 ? -balance : balance),
                    balance >= 0 ? 'Còn lại' : 'Âm',
                    balance >= 0 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardItem(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaterSummaryCard(BuildContext context) {
    final glasses = (_waterCurrentMl / 250).floor();
    final goalGlasses = (_waterGoalMl / 250).floor();
    final progress = _waterGoalMl > 0 ? (_waterCurrentMl / _waterGoalMl).clamp(0.0, 1.0) : 0.0;
    
    String statusText;
    if (_waterCurrentMl == 0) {
      statusText = '$glasses/$goalGlasses ly - Bắt đầu uống nước nào! 💧';
    } else if (_waterCurrentMl >= _waterGoalMl) {
      statusText = '$glasses/$goalGlasses ly - Đã đủ mục tiêu! 🎉';
    } else {
      final remaining = _waterGoalMl - _waterCurrentMl;
      statusText = '$glasses/$goalGlasses ly - Còn ${remaining}ml nữa 💧';
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.water_drop,
                  color: Colors.lightBlueAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nhắc nhở uống nước',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mục tiêu: ${_waterGoalMl}ml / ngày',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation(Colors.lightBlueAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseSummaryCard(BuildContext context) {
    final balance = _totalIncome - _totalExpense;
    
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.greenAccent,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quản lý chi tiêu',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tháng này',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildExpenseItem(context, 'Thu nhập', _formatCurrency(_totalIncome), Colors.greenAccent),
              _buildExpenseItem(context, 'Chi tiêu', _formatCurrency(_totalExpense), Colors.redAccent),
              _buildExpenseItem(context, 'Còn lại', _formatCurrency(balance), Colors.lightBlueAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem(BuildContext context, String label, String amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Water Reminder Screen - Nhắc nhở uống nước (theo spec 4.2)
class WaterReminderScreen extends StatefulWidget {
  const WaterReminderScreen({super.key});

  @override
  State<WaterReminderScreen> createState() => _WaterReminderScreenState();
}

class _WaterReminderScreenState extends State<WaterReminderScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Thông tin người dùng
  double _weight = 60.0; // kg
  double _height = 165.0; // cm
  
  // Mục tiêu và tiến độ
  int _dailyGoalMl = 2000;
  int _currentMl = 0;
  bool _hasAskedContinue = false; // Đã hỏi tiếp tục uống chưa
  
  // Cài đặt nhắc nhở
  bool _reminderEnabled = false;
  String _notificationMode = 'sound'; // 'sound', 'vibrate', 'both', 'silent'
  
  // Interval nhắc nhở (có test options)
  int _reminderIntervalMinutes = 30;
  DateTime? _reminderStartedAt; // Thời điểm bật nhắc nhở
  
  // Options cho interval
  static const List<Map<String, dynamic>> _intervalOptions = [
    {'value': 1, 'label': '30 giây (test)', 'seconds': 30},
    {'value': 2, 'label': '1 phút (test)', 'seconds': 60},
    {'value': 15, 'label': '15 phút', 'seconds': 900},
    {'value': 30, 'label': '30 phút', 'seconds': 1800},
    {'value': 45, 'label': '45 phút', 'seconds': 2700},
    {'value': 60, 'label': '60 phút', 'seconds': 3600},
  ];
  
  String _getIntervalLabel(int value) {
    final opt = _intervalOptions.firstWhere(
      (o) => o['value'] == value, 
      orElse: () => {'label': '$value phút'},
    );
    return opt['label'] as String;
  }
  
  Duration _getIntervalDuration() {
    final opt = _intervalOptions.firstWhere(
      (o) => o['value'] == _reminderIntervalMinutes,
      orElse: () => {'seconds': _reminderIntervalMinutes * 60},
    );
    return Duration(seconds: opt['seconds'] as int);
  }
  
  // Lịch sử uống nước hôm nay
  final List<Map<String, dynamic>> _todayHistory = [];
  
  // Lịch sử các ngày trước (load từ SharedPreferences)
  List<Map<String, dynamic>> _weekHistory = [];
  
  /// Tạo date key cho SharedPreferences: "2026-03-07"
  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
  
  String get _todayKey => _dateKey(DateTime.now());
  
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadReminderSettings();
    _loadWaterData();
    _loadUserProfile();
  }

  /// Load weight/height từ SharedPreferences (đồng bộ từ mọi nguồn)
  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final hs = HealthService();
    
    // Ưu tiên lấy height từ health service (user_height_cm)
    double? h = await hs.getHeight();
    // Fallback sang profile_height
    if (h == null) {
      final profileH = prefs.getString('profile_height') ?? '';
      if (profileH.isNotEmpty) h = double.tryParse(profileH);
    }
    
    // Ưu tiên lấy weight từ health service (weight_history)
    double? w = await hs.getLatestWeight();
    // Fallback sang profile_weight
    if (w == null) {
      final profileW = prefs.getString('profile_weight') ?? '';
      if (profileW.isNotEmpty) w = double.tryParse(profileW);
    }
    
    // Nếu vẫn thiếu thì sync từ Firestore profile
    if (w == null || h == null) {
      final cloud = await FirestoreService().loadProfile();
      if (cloud != null) {
        final cloudH = cloud['height'] as String? ?? '';
        final cloudW = cloud['weight'] as String? ?? '';
        if (h == null && cloudH.isNotEmpty) {
          h = double.tryParse(cloudH);
        }
        if (w == null && cloudW.isNotEmpty) {
          w = double.tryParse(cloudW);
        }
        if (cloudH.isNotEmpty) {
          await prefs.setString('profile_height', cloudH);
        }
        if (cloudW.isNotEmpty) {
          await prefs.setString('profile_weight', cloudW);
        }
        final hVal = h;
        final wVal = w;
        if (hVal != null && hVal > 0) await hs.saveHeight(hVal);
        if (wVal != null && wVal > 0) await hs.saveWeight(wVal);
      }
    }

    if (mounted) {
      setState(() {
        if (w != null) _weight = w;
        if (h != null) _height = h;
      });
    }
  }

  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _reminderEnabled = prefs.getBool('water_reminder_enabled') ?? false;
      _reminderIntervalMinutes = prefs.getInt('water_reminder_interval_value') ?? 30;
      _notificationMode = prefs.getString('water_notification_mode') ?? 'both';
    });
    if (_reminderEnabled) {
      _scheduleBackgroundNotifications();
    }
  }

  /// Load dữ liệu uống nước theo ngày từ SharedPreferences, sync từ Firestore nếu local trống
  Future<void> _loadWaterData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey;
    
    // Kiểm tra ngày mới → reset nếu cần
    final lastDate = prefs.getString('water_last_date') ?? '';
    if (lastDate != today) {
      // Lưu dữ liệu ngày cũ vào history trước khi reset
      if (lastDate.isNotEmpty) {
        final oldMl = prefs.getInt('water_current_ml') ?? 0;
        if (oldMl > 0) {
          await prefs.setInt('water_history_$lastDate', oldMl);
        }
      }
      // Reset cho ngày mới
      await prefs.setInt('water_current_ml', 0);
      await prefs.setString('water_last_date', today);
      await prefs.remove('water_today_entries');
    }
    
    // Load dữ liệu hôm nay từ local
    int currentMl = prefs.getInt('water_current_ml') ?? 0;
    final entries = prefs.getStringList('water_today_entries') ?? [];
    
    final List<Map<String, dynamic>> loadedHistory = [];
    for (final entry in entries) {
      // Format: "timestamp|amount"
      final parts = entry.split('|');
      if (parts.length == 2) {
        loadedHistory.add({
          'id': int.tryParse(parts[0]) ?? 0,
          'time': DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[0]) ?? 0),
          'amount': int.tryParse(parts[1]) ?? 0,
        });
      }
    }

    // Nếu local trống → sync từ Firestore (cài lại app / đổi tài khoản)
    if (currentMl == 0 && entries.isEmpty) {
      try {
        final cloudToday = await FirestoreService().loadWaterDaily(today);
        if (cloudToday != null) {
          currentMl = (cloudToday['totalMl'] as num?)?.toInt() ?? 0;
          final goalMl = (cloudToday['goalMl'] as num?)?.toInt() ?? 0;
          if (currentMl > 0) {
            await prefs.setInt('water_current_ml', currentMl);
            if (goalMl > 0) await prefs.setInt('water_daily_goal_ml', goalMl);
            await prefs.setString('water_last_date', today);
            // Load entries từ Firestore
            final cloudEntries = cloudToday['entries'] as List<dynamic>?;
            if (cloudEntries != null) {
              for (final e in cloudEntries) {
                final ts = (e['timestamp'] as num?)?.toInt() ?? 0;
                final amount = (e['amount'] as num?)?.toInt() ?? 0;
                loadedHistory.add({
                  'id': ts,
                  'time': DateTime.fromMillisecondsSinceEpoch(ts),
                  'amount': amount,
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Sync water today from Firestore error: $e');
      }
    }
    
    // Load lịch sử 7 ngày trước
    final List<Map<String, dynamic>> weekData = [];
    bool hasLocalHistory = false;
    for (int i = 1; i <= 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _dateKey(date);
      final amount = prefs.getInt('water_history_$key') ?? 0;
      if (amount > 0) hasLocalHistory = true;
      weekData.add({'date': date, 'amount': amount});
    }
    
    // Nếu local history trống → sync từ Firestore
    if (!hasLocalHistory) {
      try {
        final cloudHistory = await FirestoreService().loadWaterHistory(7);
        if (cloudHistory.isNotEmpty) {
          weekData.clear();
          for (final item in cloudHistory) {
            final date = item['date'] as DateTime;
            final amount = (item['amount'] as num?)?.toInt() ?? 0;
            weekData.add({'date': date, 'amount': amount});
            // Cache lại vào local
            if (amount > 0) {
              await prefs.setInt('water_history_${_dateKey(date)}', amount);
            }
          }
        }
      } catch (e) {
        debugPrint('Sync water history from Firestore error: $e');
      }
    }
    
    setState(() {
      _currentMl = currentMl;
      _todayHistory.clear();
      _todayHistory.addAll(loadedHistory);
      _weekHistory = weekData.reversed.toList();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  // Lên lịch notification cho background (khi app đóng)
  Future<bool> _scheduleBackgroundNotifications() async {
    if (kIsWeb) return false;
    if (!_reminderEnabled) return false;
    
    try {
      await NotificationService().initialize();

      // Yêu cầu quyền notification (Android 13+)
      final notifPermission = await NotificationService().requestPermission();
      if (!notifPermission) {
        debugPrint('⚠️ Notification permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lòng cấp quyền thông báo để nhận nhắc nhở')),
          );
        }
        return false;
      }
      
      // Yêu cầu quyền exact alarm (Android 12+)
      if (!kIsWeb && Platform.isAndroid) {
        final exactAlarmOk = await NotificationService().requestExactAlarmPermission();
        if (!exactAlarmOk) {
          debugPrint('⚠️ Exact alarm permission denied');
        }
        
        // Kiểm tra quyền hiển thị trên ứng dụng khác
        final canOverlay = await NotificationService().canDrawOverlays();
        final batteryOptimized = await NotificationService().isBatteryOptimized();
        
        if ((!canOverlay || batteryOptimized) && mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cần cấp thêm quyền'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Để nhắc nhở hiện full màn hình khi khóa màn hình, cần bật:'),
                  const SizedBox(height: 12),
                  if (!canOverlay) 
                    const Text('• Hiển thị trên ứng dụng khác'),
                  if (batteryOptimized)
                    const Text('• Tắt tối ưu pin cho BetterME'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Để sau'),
                ),
                if (!canOverlay)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NotificationService().openOverlaySettings();
                    },
                    child: const Text('Cấp quyền overlay'),
                  ),
                if (canOverlay && batteryOptimized)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NotificationService().openBatterySettings();
                    },
                    child: const Text('Tắt tối ưu pin'),
                  ),
              ],
            ),
          );
        }
      }
      
      final interval = _getIntervalDuration();
      
      // Lên lịch notification
      final scheduledCount = await NotificationService().schedulePeriodicNotification(
        id: 1,
        title: 'Đã đến uống nước!',
        body: 'Gợi ý: ${_suggestedAmountPerDrink}ml. Uống ngay!',
        interval: interval,
        payload: 'water_reminder',
      );
      if (scheduledCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không lên lịch được nhắc nhở. Vui lòng kiểm tra quyền thông báo.'),
            ),
          );
        }
        return false;
      }

      debugPrint('✅ Background notifications scheduled: $scheduledCount items');
      return true;
    } catch (e) {
      debugPrint('❌ Error scheduling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lên lịch nhắc nhở: $e')),
        );
      }
      return false;
    }
  }
  
  Future<void> _stopBackgroundNotifications() async {
    if (kIsWeb) return;
    await NotificationService().stopWaterReminder();
  }

  /// Cập nhật chế độ thông báo + re-schedule notifications ngay
  Future<void> _updateNotificationMode(String mode) async {
    setState(() => _notificationMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('water_notification_mode', mode);
    
    // Re-schedule notifications với mode mới
    if (_reminderEnabled) {
      await _scheduleBackgroundNotifications();
    }
  }

  /// Dialog cho người dùng chọn số ml khi bấm "Uống ngay"
  void _showQuickWaterSelectDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '💧 Chọn lượng nước bạn uống',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Gợi ý: ${_suggestedAmountPerDrink}ml',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [100, 150, 200, 250, 300, 500].map((ml) {
                  final isSuggested = ml == ((_suggestedAmountPerDrink ~/ 50) * 50);
                  return ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _addWater(ml);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSuggested ? Colors.blue : Colors.blue.withOpacity(0.1),
                      foregroundColor: isSuggested ? Colors.white : Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text('${ml}ml'),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showCustomAmountDialog();
                },
                child: const Text('Nhập số khác'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  double get _progress => _dailyGoalMl > 0 ? _currentMl / _dailyGoalMl : 0;
  
  // Tính lượng nước gợi ý mỗi lần uống - TỰ ĐỘNG ĐIỀU CHỈNH
  int get _suggestedAmountPerDrink {
    final remaining = _dailyGoalMl - _currentMl;
    if (remaining <= 0) return 200; // Đã đạt mục tiêu
    
    // Tính số lần nhắc còn lại đến 22:00
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 22, 0); // Giả sử ngừng uống trước 22h
    
    if (now.isAfter(endOfDay)) return remaining.clamp(100, 500);
    
    final remainingMinutes = endOfDay.difference(now).inMinutes;
    final intervalMinutes = _getIntervalDuration().inSeconds / 60;
    final remainingReminders = (remainingMinutes / intervalMinutes).floor();
    
    if (remainingReminders <= 0) return remaining.clamp(100, 500);
    
    // Chia đều lượng nước còn lại cho số lần nhắc còn lại
    final suggested = (remaining / remainingReminders).round();
    return suggested.clamp(100, 500); // Min 100ml, max 500ml mỗi lần
  }

  void _addWater(int ml) {
    // Kiểm tra nếu đã đủ mục tiêu và chưa hỏi
    if (_currentMl >= _dailyGoalMl && !_hasAskedContinue) {
      _showContinueDialog(ml);
      return;
    }
    
    setState(() {
      _currentMl += ml;
      _todayHistory.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'time': DateTime.now(),
        'amount': ml,
      });
    });
    
    // Sync lên SharedPreferences để HomeScreen đọc được
    _syncWaterProgress();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã uống ${ml}ml'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ),
    );
    
    // Chỉ hiển thị chúc mừng khi vừa đạt mục tiêu
    if (_currentMl >= _dailyGoalMl && _currentMl - ml < _dailyGoalMl) {
      _showCongratulations();
    }
  }
  
  /// Sync tiến độ uống nước lên SharedPreferences + Firestore
  Future<void> _syncWaterProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_current_ml', _currentMl);
    await prefs.setInt('water_daily_goal_ml', _dailyGoalMl);
    await prefs.setString('water_last_date', _todayKey);
    
    // Lưu lịch sử entries hôm nay
    final entries = _todayHistory.map((e) {
      final time = e['time'] as DateTime;
      return '${time.millisecondsSinceEpoch}|${e['amount']}';
    }).toList();
    await prefs.setStringList('water_today_entries', entries);
    
    // Lưu tổng ml hôm nay vào history key
    await prefs.setInt('water_history_$_todayKey', _currentMl);
    
    // Đồng bộ lên Firestore
    FirestoreService().saveWaterDaily(
      dateKey: _todayKey,
      totalMl: _currentMl,
      goalMl: _dailyGoalMl,
      entries: _todayHistory,
    );
  }

  void _showContinueDialog(int ml) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đã đủ mục tiêu!'),
        content: Text(
          'Bạn đã uống đủ ${_dailyGoalMl}ml hôm nay.\n'
          'Bạn có muốn tiếp tục uống thêm không?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _hasAskedContinue = true;
              });
              _addWater(ml);
            },
            child: const Text('Uống tiếp'),
          ),
        ],
      ),
    );
  }

  void _showCongratulations() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tuyệt vời!'),
        content: const Text(
          'Bạn đã hoàn thành mục tiêu uống nước hôm nay!\n'
          'Tiếp tục duy trì nhé!'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _editHistoryEntry(int index) {
    final entry = _todayHistory[index];
    final controller = TextEditingController(text: entry['amount'].toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa lượng nước'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Lượng nước (ml)',
                suffixText: 'ml',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thời gian: ${_formatTime(entry['time'] as DateTime)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Xóa entry
              setState(() {
                _currentMl -= entry['amount'] as int;
                _todayHistory.removeAt(index);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã xóa')),
              );
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final newAmount = int.tryParse(controller.text);
              if (newAmount != null && newAmount > 0) {
                setState(() {
                  _currentMl = _currentMl - (entry['amount'] as int) + newAmount;
                  _todayHistory[index]['amount'] = newAmount;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _resetToday() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đặt lại hôm nay?'),
        content: const Text('Tất cả lịch sử uống nước hôm nay sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _currentMl = 0;
                _todayHistory.clear();
                _hasAskedContinue = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã đặt lại')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đặt lại'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Nhắc nhở uống nước', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Uống nước'),
            Tab(text: 'Nhắc nhở'),
            Tab(text: 'Lịch sử'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDrinkTab(),
          _buildRemindersTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  // Tab 1: Uống nước
  Widget _buildDrinkTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Ly nước rót đầy dần
          WaterGlassWidget(
            progress: _progress,
            currentMl: _currentMl,
            goalMl: _dailyGoalMl,
          ),
          const SizedBox(height: 24),
          
          
          // Chọn mục tiêu
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mục tiêu hôm nay',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [2000, 2500, 3000].map((goal) => 
                      ChoiceChip(
                        label: Text('${goal}ml'),
                        selected: _dailyGoalMl == goal,
                        selectedColor: Colors.blue.withOpacity(0.2),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _dailyGoalMl = goal);
                          }
                        },
                      ),
                    ).toList(),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _showCustomGoalDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Tùy chỉnh'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Quick add buttons
          Text(
            'Chọn lượng nước',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [100, 200, 250, 300, 500].map((ml) => 
              _buildWaterButton(ml),
            ).toList(),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _showCustomAmountDialog,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Nhập số khác'),
          ),
          
          const SizedBox(height: 24),
          
          // Today's quick history
          if (_todayHistory.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hôm nay (${_todayHistory.length} lần)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(2),
                  child: const Text('Xem chi tiết →'),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildWaterButton(int ml) {
    final isSuggested = ml == ((_suggestedAmountPerDrink ~/ 50) * 50);
    return ElevatedButton(
      onPressed: () => _addWater(ml),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSuggested ? Colors.green : Colors.blue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${ml}ml', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (isSuggested) 
            const Text('Gợi ý', style: TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  void _showEditProfileDialog() {
    final weightController = TextEditingController(text: _weight.toString());
    final heightController = TextEditingController(text: _height.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thông tin cá nhân'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cân nặng',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chiều cao',
                suffixText: 'cm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final weight = double.tryParse(weightController.text);
              final height = double.tryParse(heightController.text);
              if (weight != null && height != null && weight > 20 && weight < 300 && height > 50 && height < 300) {
                final prefs = await SharedPreferences.getInstance();
                final hs = HealthService();
                
                // Lưu vào health service (user_height_cm + weight_history)
                await hs.saveHeight(height);
                await hs.saveWeight(weight);
                
                // Đồng bộ sang profile keys
                await prefs.setString('profile_height', height.toStringAsFixed(0));
                await prefs.setString('profile_weight', weight.toStringAsFixed(1));
                
                setState(() {
                  _weight = weight;
                  _height = height;
                });
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showCustomGoalDialog() {
    final controller = TextEditingController(text: _dailyGoalMl.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mục tiêu tùy chỉnh'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Lượng nước',
            suffixText: 'ml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final goal = int.tryParse(controller.text);
              if (goal != null && goal > 0) {
                setState(() => _dailyGoalMl = goal);
                Navigator.pop(context);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showCustomAmountDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nhập lượng nước'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Số ml',
            suffixText: 'ml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final ml = int.tryParse(controller.text);
              if (ml != null && ml > 0) {
                Navigator.pop(context);
                _addWater(ml);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  // Tab 2: Nhắc nhở
  Widget _buildRemindersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bật/tắt nhắc nhở
          Card(
            child: SwitchListTile(
              title: const Text('Nhắc nhở uống nước'),
              subtitle: Text(
                _reminderEnabled 
                    ? 'Mỗi ${_getIntervalLabel(_reminderIntervalMinutes)} • Bắt đầu từ ${_reminderStartedAt != null ? _formatTime(_reminderStartedAt!) : "bây giờ"}'
                    : 'Đã tắt',
              ),
              value: _reminderEnabled,
              onChanged: (value) async {
                setState(() {
                  _reminderEnabled = value;
                  if (value) {
                    _reminderStartedAt = DateTime.now();
                  } else {
                    _reminderStartedAt = null;
                  }
                });
                
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('water_reminder_enabled', value);
                
                if (value) {
                  final success = await _scheduleBackgroundNotifications();
                  if (success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Đã bật nhắc nhở mỗi ${_getIntervalLabel(_reminderIntervalMinutes)}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else if (!success && mounted) {
                    // Revert toggle nếu không lên lịch được
                    setState(() {
                      _reminderEnabled = false;
                      _reminderStartedAt = null;
                    });
                    await prefs.setBool('water_reminder_enabled', false);
                  }
                } else {
                  await _stopBackgroundNotifications();
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          
          if (_reminderEnabled) ...[
            // Chế độ thông báo
            Text(
              'Chế độ thông báo',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('Chuông'),
                    subtitle: const Text('Phát âm thanh khi nhắc nhở'),
                    value: 'sound',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Rung'),
                    subtitle: Text(Platform.isIOS
                        ? 'Không âm thanh (rung theo cài đặt iPhone)'
                        : 'Chỉ rung liên tục, không có âm thanh'),
                    value: 'vibrate',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Chuông + Rung'),
                    subtitle: const Text('Cả âm thanh và rung liên tục'),
                    value: 'both',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Im lặng'),
                    subtitle: const Text('Chỉ hiện thông báo'),
                    value: 'silent',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Khoảng cách nhắc nhở
            Text(
              'Khoảng cách nhắc nhở',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Nhắc mỗi'),
                        DropdownButton<int>(
                          value: _reminderIntervalMinutes,
                          items: _intervalOptions.map((opt) => 
                            DropdownMenuItem(
                              value: opt['value'] as int,
                              child: Text(opt['label'] as String),
                            ),
                          ).toList(),
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() {
                                _reminderIntervalMinutes = value;
                              });
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setInt('water_reminder_interval_value', value);
                              await _scheduleBackgroundNotifications();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Thông tin tự động điều chỉnh
            Card(
              color: Colors.green.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Tự động điều chỉnh',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.water_drop, 'Đã uống', '$_currentMl / $_dailyGoalMl ml'),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.local_drink, 'Còn lại', '${(_dailyGoalMl - _currentMl).clamp(0, _dailyGoalMl)} ml'),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.recommend, 'Gợi ý lần tới', '${_suggestedAmountPerDrink} ml'),
                    if (_todayHistory.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildInfoRow(Icons.trending_up, 'TB mỗi lần', '${(_currentMl / _todayHistory.length).round()} ml'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  // Tab 3: Lịch sử
  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lịch sử hôm nay
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hôm nay',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                children: [
                  Text(
                    '${_currentMl}ml',
                    style: TextStyle(
                      color: _progress >= 1.0 ? Colors.green : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _resetToday,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          if (_todayHistory.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Chưa uống nước hôm nay',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ),
            )
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _todayHistory.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _todayHistory[_todayHistory.length - 1 - index];
                  final actualIndex = _todayHistory.length - 1 - index;
                  final time = entry['time'] as DateTime;
                  
                  return ListTile(
                    title: Text('${entry['amount']}ml'),
                    subtitle: Text(_formatTime(time)),
                    trailing: TextButton(
                      onPressed: () => _editHistoryEntry(actualIndex),
                      child: const Text('Sửa'),
                    ),
                  );
                },
              ),
            ),
          
          const SizedBox(height: 24),
          
          // Weekly chart
          Text(
            'Tuần này',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ..._weekHistory.map((day) {
                  final amount = day['amount'] as int;
                  final percent = _dailyGoalMl > 0 ? amount / _dailyGoalMl : 0.0;
                  
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${(percent * 100).toInt()}%',
                            style: const TextStyle(fontSize: 9),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 120 * percent.clamp(0.0, 1.0),
                            decoration: BoxDecoration(
                              color: percent >= 1.0 
                                  ? Colors.green.withOpacity(0.7)
                                  : Colors.blue.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getDayLabel(day['date'] as DateTime),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // Today
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: 120 * _progress.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: _progress >= 1.0 ? Colors.green : Colors.blue,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Nay',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Stats
          Text(
            'Thống kê',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Trung bình',
                  '${_getAverageIntake()}ml',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Streak',
                  '${_getStreak()} ngày',
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Hoàn thành',
                  '${_getCompletedDays()}/7',
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Cao nhất',
                  '${_getMaxIntake()}ml',
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDayLabel(DateTime date) {
    const days = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    return days[date.weekday % 7];
  }

  int _getAverageIntake() {
    if (_weekHistory.isEmpty) return 0;
    final total = _weekHistory.fold<int>(0, (sum, day) => sum + (day['amount'] as int));
    return (total / _weekHistory.length).round();
  }

  int _getStreak() {
    int streak = _currentMl >= _dailyGoalMl ? 1 : 0;
    for (int i = _weekHistory.length - 1; i >= 0; i--) {
      if (_weekHistory[i]['amount'] >= _dailyGoalMl) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  int _getCompletedDays() {
    int completed = _currentMl >= _dailyGoalMl ? 1 : 0;
    completed += _weekHistory.where((d) => d['amount'] >= _dailyGoalMl).length;
    return completed;
  }

  int _getMaxIntake() {
    final todayMax = _currentMl;
    final historyMax = _weekHistory.isEmpty 
        ? 0 
        : _weekHistory.map((d) => d['amount'] as int).reduce((a, b) => a > b ? a : b);
    return todayMax > historyMax ? todayMax : historyMax;
  }
}

/// Expense Screen - Quản lý chi tiêu
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  final List<Map<String, dynamic>> _transactions = [];
  
  double get _totalIncome => _transactions
      .where((t) => t['type'] == 'income')
      .fold(0.0, (sum, t) => sum + (t['amount'] as double));
  
  double get _totalExpense => _transactions
      .where((t) => t['type'] == 'expense')
      .fold(0.0, (sum, t) => sum + (t['amount'] as double));
  
  double get _balance => _totalIncome - _totalExpense;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  /// Load giao dịch từ SharedPreferences, rồi sync từ Firestore
  Future<void> _loadTransactions() async {
    // Load local trước cho nhanh
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('expense_transactions') ?? [];
    
    final List<Map<String, dynamic>> loaded = [];
    for (final entry in data) {
      // Format: "type|amount|category|note|timestamp"
      final parts = entry.split('|');
      if (parts.length >= 5) {
        loaded.add({
          'type': parts[0],
          'amount': double.tryParse(parts[1]) ?? 0.0,
          'category': parts[2],
          'note': parts[3],
          'date': DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[4]) ?? 0),
        });
      }
    }
    
    setState(() {
      _transactions.clear();
      _transactions.addAll(loaded);
    });
    
    // Sync từ Firestore nếu local trống
    if (loaded.isEmpty) {
      final cloudData = await FirestoreService().loadTransactions();
      if (cloudData.isNotEmpty && mounted) {
        setState(() {
          _transactions.clear();
          _transactions.addAll(cloudData);
        });
        // Lưu lại local
        final localData = _transactions.map((t) {
          final date = t['date'] as DateTime;
          return '${t['type']}|${t['amount']}|${t['category']}|${t['note'] ?? ''}|${date.millisecondsSinceEpoch}';
        }).toList();
        await prefs.setStringList('expense_transactions', localData);
      }
    }
  }

  /// Lưu giao dịch vào SharedPreferences + Firestore
  Future<void> _saveTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _transactions.map((t) {
      final date = t['date'] as DateTime;
      return '${t['type']}|${t['amount']}|${t['category']}|${t['note'] ?? ''}|${date.millisecondsSinceEpoch}';
    }).toList();
    await prefs.setStringList('expense_transactions', data);
    
    // Đồng bộ lên Firestore
    FirestoreService().saveTransactions(_transactions);
  }

  void _showAddTransactionDialog({bool isIncome = false}) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String selectedCategory = isIncome ? 'Lương' : 'Ăn uống';
    
    final incomeCategories = ['Lương', 'Thưởng', 'Đầu tư', 'Khác'];
    final expenseCategories = ['Ăn uống', 'Di chuyển', 'Mua sắm', 'Giải trí', 'Hóa đơn', 'Khác'];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isIncome ? 'Thêm thu nhập' : 'Thêm chi tiêu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: isIncome ? Colors.green : Colors.red,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Amount
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Số tiền',
                  prefixText: 'đ ',
                  prefixIcon: Icon(
                    isIncome ? Icons.add_circle : Icons.remove_circle,
                    color: isIncome ? Colors.green : Colors.red,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Category
              Text('Danh mục', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: (isIncome ? incomeCategories : expenseCategories)
                    .map((cat) => ChoiceChip(
                          label: Text(cat),
                          selected: selectedCategory == cat,
                          selectedColor: isIncome 
                              ? Colors.green.withOpacity(0.2) 
                              : Colors.red.withOpacity(0.2),
                          onSelected: (selected) {
                            if (selected) {
                              setModalState(() => selectedCategory = cat);
                            }
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              
              // Note
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (tùy chọn)',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 24),
              
              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(amountController.text);
                    if (amount != null && amount > 0) {
                      setState(() {
                        _transactions.add({
                          'type': isIncome ? 'income' : 'expense',
                          'amount': amount,
                          'category': selectedCategory,
                          'note': noteController.text,
                          'date': DateTime.now(),
                        });
                      });
                      _saveTransactions();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isIncome 
                                ? 'Đã thêm thu nhập ${_formatCurrency(amount)}'
                                : 'Đã thêm chi tiêu ${_formatCurrency(amount)}',
                          ),
                          backgroundColor: isIncome ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIncome ? Colors.green : Colors.red,
                  ),
                  child: const Text('Lưu'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}k';
    }
    return '${amount.toStringAsFixed(0)}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Quản lý chi tiêu', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Summary card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  'Số dư',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatCurrency(_balance),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      context,
                      'Thu nhập',
                      _formatCurrency(_totalIncome),
                      Icons.arrow_downward,
                      Colors.greenAccent,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white30,
                    ),
                    _buildSummaryItem(
                      context,
                      'Chi tiêu',
                      _formatCurrency(_totalExpense),
                      Icons.arrow_upward,
                      Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTransactionDialog(isIncome: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Thu nhập'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTransactionDialog(isIncome: false),
                    icon: const Icon(Icons.remove),
                    label: const Text('Chi tiêu'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Transactions list
          Expanded(
            child: _transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: AppColors.grey.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chưa có giao dịch nào',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bấm nút trên để thêm thu nhập/chi tiêu',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final transaction = _transactions[_transactions.length - 1 - index];
                      final isIncome = transaction['type'] == 'income';
                      final date = transaction['date'] as DateTime;
                      
                      return Dismissible(
                        key: Key('$index-${transaction['date']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          setState(() {
                            _transactions.removeAt(_transactions.length - 1 - index);
                          });
                          _saveTransactions();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã xóa giao dịch')),
                          );
                        },
                        child: Card(
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isIncome ? Colors.green : Colors.red)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(transaction['category'] as String),
                            subtitle: Text(
                              transaction['note']?.isNotEmpty == true
                                  ? transaction['note'] as String
                                  : '${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                            ),
                            trailing: Text(
                              '${isIncome ? '+' : '-'}${_formatCurrency(transaction['amount'] as double)}',
                              style: TextStyle(
                                color: isIncome ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String amount,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
