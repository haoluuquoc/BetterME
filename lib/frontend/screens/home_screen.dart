import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/notification_service.dart';
import '../../services/firestore_service.dart';
import '../../services/health_service.dart';
import 'water_alarm_screen.dart';
import 'update_alarm_screen.dart';
import 'settings_screen.dart';
import 'health_screen.dart';
import '../widgets/water_glass_widget.dart';

/// Home Screen - MÃ n hÃ¬nh chÃ­nh
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
    // Kiá»ƒm tra cáº­p nháº­t khi má»Ÿ app
    if (!kIsWeb && Platform.isAndroid) {
      _checkForAppUpdate();
    }
  }
  
  /// Kiá»ƒm tra flag navigate_to_tab (tá»« "Uá»‘ng ngay" trÃªn alarm screen khi launch tá»« notification)
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
      // KhÃ´ng check náº¿u vá»«a dismiss alarm screen trong 2 giÃ¢y gáº§n Ä‘Ã¢y
      if (_lastAlarmDismissed != null) {
        final diff = DateTime.now().difference(_lastAlarmDismissed!);
        if (diff.inSeconds < 2) return;
      }
      // App vá»«a quay láº¡i foreground â†’ kiá»ƒm tra cÃ³ pending alarm khÃ´ng
      _checkPendingNotification();
      
      // iOS: kiá»ƒm tra notification Ä‘Ã£ fire trong lÃºc á»Ÿ background
      // VÃ  reschedule thÃªm notifications (iOS giá»›i háº¡n 64 pending)
      if (!kIsWeb && Platform.isIOS) {
        _checkIOSAlarmAndReschedule();
      }
    }
  }
  
  /// iOS: reschedule notifications khi app resumed (iOS giá»›i háº¡n 64 pending)
  /// Hiá»‡n popup nháº¹ thay vÃ¬ alarm screen toÃ n mÃ n hÃ¬nh
  void _checkIOSAlarmAndReschedule() async {
    // Reschedule Ä‘á»ƒ luÃ´n cÃ³ Ä‘á»§ notifications cho tÆ°Æ¡ng lai
    NotificationService().rescheduleWaterReminder();
    
    // Kiá»ƒm tra xem cÃ³ alarm Ä‘Ã£ fire chÆ°a xá»­ lÃ½ khÃ´ng â†’ hiá»‡n popup
    final shouldShowAlarm = await NotificationService().checkIOSPendingAlarm();
    if (shouldShowAlarm && mounted && !_isAlarmShowing) {
      _showWaterReminderPopup();
    }
  }
  
  /// Listener: nháº­n signal tá»« IsolateNameServer khi app Ä‘ang má»Ÿ
  void _setupAlarmListener() {
    if (kIsWeb) return;
    _alarmSubscription = NotificationService.onAlarmFired.listen((_) async {
      if (!kIsWeb && Platform.isIOS) {
        return;
      }
      // Reset block flag khi cÃ³ alarm má»›i (dÃ¹ng SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('block_alarm_screen', false);
      
      if (mounted && !_isAlarmShowing) {
        // Check náº¿u lÃ  snooze (tá»« snooze callback)
        final wasSnooze = prefs.getBool('water_snooze_just_fired') ?? false;
        await prefs.setBool('water_snooze_just_fired', false);
        _showAlarmScreen(isSnooze: wasSnooze);
      }
    });
  }
  
  /// Listener: nháº­n signal update alarm
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
  
  /// Hiá»‡n UpdateAlarmScreen full-screen kiá»ƒu bÃ¡o thá»©c
  void _showUpdateAlarmScreen() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const UpdateAlarmScreen(),
      ),
    );
    
    if (result == 'update') {
      // Chuyá»ƒn sang tab Settings (index 4 vÃ¬ thÃªm tab Sá»©c khá»e)
      _openTab(4);
    }
  }
  
  /// Hiá»‡n WaterAlarmScreen full-screen kiá»ƒu bÃ¡o thá»©c
  void _showAlarmScreen({bool isSnooze = false}) async {
    if (_isAlarmShowing) return;
    
    // Check block flag tá»« SharedPreferences
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
    // result == 'snooze' â†’ Ä‘Ã£ xá»­ lÃ½ trong WaterAlarmScreen
  }
  
  /// Popup nháº¹ thay tháº¿ alarm screen trÃªn iOS
  /// Hiá»‡n dialog nhá» vá»›i "Uá»‘ng ngay" / "Äá»ƒ sau" thay vÃ¬ toÃ n mÃ n hÃ¬nh vÃ ng Ä‘en
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
            Text('ðŸ’§', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            const Text('Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c'),
          ],
        ),
        content: const Text(
          'ÄÃ£ Ä‘áº¿n lÃºc uá»‘ng nÆ°á»›c rá»“i! ðŸ¥¤\nHÃ£y uá»‘ng má»™t cá»‘c nÆ°á»›c Ä‘á»ƒ giá»¯ sá»©c khá»e nhÃ©.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'snooze'),
            child: const Text('Äá»ƒ sau'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'drink'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Uá»‘ng ngay'),
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
  
  /// Kiá»ƒm tra má»¥c tiÃªu vÃ  há»i ngÆ°á»i dÃ¹ng cÃ³ muá»‘n tiáº¿p tá»¥c nháº¯c khÃ´ng
  void _checkGoalAndAskContinue() async {
    final prefs = await SharedPreferences.getInstance();
    final currentMl = prefs.getInt('water_current_ml') ?? 0;
    final goalMl = prefs.getInt('water_daily_goal_ml') ?? 2000;
    
    if (currentMl >= goalMl) {
      // ÄÃ£ Ä‘áº¡t má»¥c tiÃªu â†’ há»i cÃ³ muá»‘n tiáº¿p tá»¥c nháº¯c khÃ´ng
      if (!mounted) return;
      final continueReminder = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('ÄÃ£ Ä‘á»§ má»¥c tiÃªu!'),
          content: Text(
            'Báº¡n Ä‘Ã£ uá»‘ng Ä‘á»§ ${goalMl}ml hÃ´m nay.\n'
            'Báº¡n cÃ³ muá»‘n tiáº¿p tá»¥c nháº­n nháº¯c nhá»Ÿ khÃ´ng?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('KhÃ´ng, táº¯t nháº¯c nhá»Ÿ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Tiáº¿p tá»¥c nháº¯c'),
            ),
          ],
        ),
      );
      
      if (continueReminder == false) {
        // Tá»± táº¯t reminder
        await NotificationService().stopWaterReminder();
        await prefs.setBool('water_reminder_enabled', false);
        // Sync toggle trÃªn WaterReminderScreen
        _waterReminderKey.currentState?._loadReminderSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ÄÃ£ táº¯t nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c')),
          );
        }
      }
    }
  }
  
  // ====== AUTO UPDATE CHECK ======
  int _currentBuildNumber = 1;
  String _currentVersion = '1.0.0';

  void _checkForAppUpdate() async {
    // Äá»c version tháº­t tá»« package info
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _currentBuildNumber = int.tryParse(info.buildNumber) ?? 1;
    } catch (_) {}

    // Chá»‰ check 1 láº§n má»—i 24h
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
      // Hiá»‡n dialog cáº­p nháº­t
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
            Expanded(child: Text('CÃ³ phiÃªn báº£n má»›i $newVersion')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Báº¡n Ä‘ang dÃ¹ng: $_currentVersion',
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
                const Text('Nháº­p mÃ£ cáº­p nháº­t:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Nháº­p mÃ£...',
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
              // LÃªn lá»‹ch nháº¯c nhá»Ÿ cáº­p nháº­t sau 20 giÃ¢y (mÃ n hÃ¬nh vÃ ng Ä‘en)
              NotificationService().scheduleUpdateAlarm(
                version: newVersion,
                notes: notes,
                downloadUrl: downloadUrl,
              );
            },
            child: const Text('Äá»ƒ sau'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Cáº­p nháº­t ngay'),
            onPressed: () {
              if (needCode) {
                final entered = codeController.text.trim().toUpperCase();
                if (entered != requiredCode.toUpperCase()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('MÃ£ khÃ´ng Ä‘Ãºng')),
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
              Expanded(child: Text('Äang táº£i báº£n cáº­p nháº­t...\n${uri.host}')),
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
            SnackBar(content: Text('Lá»—i táº£i: HTTP ${response.statusCode}')),
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
          const SnackBar(content: Text('KhÃ´ng thá»ƒ cÃ i Ä‘áº·t. Kiá»ƒm tra quyá»n.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lá»—i: $e')),
        );
      }
    }
  }

  void _setupNotificationListener() {
    if (kIsWeb) return;
    
    _notificationSubscription = NotificationService.onNotificationTap.listen((payload) {
      if (payload == 'water_drink_tab') {
        // Náº¿u alarm screen Ä‘ang hiá»‡n â†’ Ä‘Ã³ng nÃ³
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
      // User báº¥m "Uá»‘ng ngay" tá»« notification â†’ vÃ o tab uá»‘ng nÆ°á»›c
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        NotificationService().cancelSnooze();
        _openTab(1);
      });
    } else if (payload == 'water_alarm_screen') {
      if (!kIsWeb && Platform.isIOS) {
        // iOS: hiá»‡n popup thay vÃ¬ alarm screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().cancelNotification(0);
          _showWaterReminderPopup();
        });
        return;
      }
      // Android: alarm screen toÃ n mÃ n hÃ¬nh
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        _showAlarmScreen();
      });
    } else if (payload == 'water_snooze') {
      if (!kIsWeb && Platform.isIOS) {
        // iOS: schedule snooze trá»±c tiáº¿p, khÃ´ng cáº§n alarm screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().cancelNotification(0);
          NotificationService().scheduleSnooze();
        });
        return;
      }
      // Android: xá»­ lÃ½ snooze tá»« notification khi app chÆ°a cháº¡y
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService().cancelNotification(0);
        NotificationService().scheduleSnooze();
        NotificationService().showSimpleNotification(
          title: 'Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c',
          body: 'Sáº½ nháº¯c láº¡i sau 20 giÃ¢y',
          payload: 'water_reminder',
        );
      });
    } else {
      // Kiá»ƒm tra pending alarm tá»« background
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A1628),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3A9BD5).withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0A1628),
          selectedItemColor: const Color(0xFF5BB5E8),
          unselectedItemColor: const Color(0xFF64748B),
          selectedFontSize: 12,
          unselectedFontSize: 11,
          elevation: 0,
          onTap: (index) {
            _openTab(index);
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Trang chủ',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.water_drop_outlined),
              activeIcon: Icon(Icons.water_drop),
              label: 'Uống nước',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: 'Chi tiêu',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_outline),
              activeIcon: Icon(Icons.favorite),
              label: 'Sức khỏe',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Cài đặt',
            ),
          ],
        ),
      ),
    );
  }
}


/// Home Content - Trang chá»§ tá»•ng quan
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

    if (mounted) {
      setState(() {
        _waterCurrentMl = currentMl;
        _waterGoalMl = goalMl;
        _totalIncome = income;
        _totalExpense = expense;
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
    return '${amount.toStringAsFixed(0)}Ä‘';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BetterME'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'LÃ m má»›i dá»¯ liá»‡u',
            onPressed: () {
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ÄÃ£ lÃ m má»›i dá»¯ liá»‡u'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
      greeting = 'ChÃ o buá»•i sÃ¡ng!';
      emoji = 'â˜€ï¸';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'ChÃ o buá»•i chiá»u!';
      emoji = 'ðŸŒ¤ï¸';
    } else if (hour >= 18 && hour < 22) {
      greeting = 'ChÃ o buá»•i tá»‘i!';
      emoji = 'ðŸŒ™';
    } else {
      greeting = 'Khuya rá»“i!';
      emoji = 'ðŸŒƒ';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting $emoji',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ChÄƒm sÃ³c sá»©c khá»e & quáº£n lÃ½ tÃ i chÃ­nh',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.grey,
          ),
        ),
      ],
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
          const Text('ðŸŽ‚', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'HÃ´m nay lÃ  sinh nháº­t $names ðŸŽ‰',
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
      onTap: () => widget.onNavigate?.call(3), // Sá»©c khá»e tab
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.dashboard,
                        color: Colors.deepPurple, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Tá»•ng quan hÃ´m nay',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.grey),
                ],
              ),
              const SizedBox(height: 16),
              // 2x2 Grid
              Row(
                children: [
                  Expanded(
                    child: _buildDashboardItem(
                      theme,
                      Icons.directions_walk,
                      '$_todaySteps',
                      'BÆ°á»›c chÃ¢n',
                      Colors.deepOrange,
                    ),
                  ),
                  Expanded(
                    child: _buildDashboardItem(
                      theme,
                      Icons.water_drop,
                      '$glasses ly',
                      'NÆ°á»›c uá»‘ng',
                      Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDashboardItem(
                      theme,
                      Icons.bedtime,
                      _todaySleep != null
                          ? '${_todaySleep!.toStringAsFixed(1)}h'
                          : '--',
                      'Giáº¥c ngá»§',
                      Colors.indigo,
                    ),
                  ),
                  Expanded(
                    child: _buildDashboardItem(
                      theme,
                      Icons.account_balance_wallet,
                      _formatCurrency(balance < 0 ? -balance : balance),
                      balance >= 0 ? 'CÃ²n láº¡i' : 'Ã‚m',
                      balance >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey,
                  fontSize: 11,
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
      statusText = '$glasses/$goalGlasses ly - Báº¯t Ä‘áº§u uá»‘ng nÆ°á»›c nÃ o! ðŸ’§';
    } else if (_waterCurrentMl >= _waterGoalMl) {
      statusText = '$glasses/$goalGlasses ly - ÄÃ£ Ä‘á»§ má»¥c tiÃªu! ðŸŽ‰';
    } else {
      final remaining = _waterGoalMl - _waterCurrentMl;
      statusText = '$glasses/$goalGlasses ly - CÃ²n ${remaining}ml ná»¯a ðŸ’§';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.water_drop,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Má»¥c tiÃªu: ${_waterGoalMl}ml / ngÃ y',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.grey),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor: const AlwaysStoppedAnimation(Colors.blue),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseSummaryCard(BuildContext context) {
    final balance = _totalIncome - _totalExpense;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quáº£n lÃ½ chi tiÃªu',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ThÃ¡ng nÃ y',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.grey),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildExpenseItem(context, 'Thu nháº­p', _formatCurrency(_totalIncome), Colors.green),
                _buildExpenseItem(context, 'Chi tiÃªu', _formatCurrency(_totalExpense), Colors.red),
                _buildExpenseItem(context, 'CÃ²n láº¡i', _formatCurrency(balance), Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseItem(BuildContext context, String label, String amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.grey,
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

/// Water Reminder Screen - Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c (theo spec 4.2)
class WaterReminderScreen extends StatefulWidget {
  const WaterReminderScreen({super.key});

  @override
  State<WaterReminderScreen> createState() => _WaterReminderScreenState();
}

class _WaterReminderScreenState extends State<WaterReminderScreen> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // ThÃ´ng tin ngÆ°á»i dÃ¹ng
  double _weight = 60.0; // kg
  double _height = 165.0; // cm
  
  // Má»¥c tiÃªu vÃ  tiáº¿n Ä‘á»™
  int _dailyGoalMl = 2000;
  int _currentMl = 0;
  bool _hasAskedContinue = false; // ÄÃ£ há»i tiáº¿p tá»¥c uá»‘ng chÆ°a
  
  // CÃ i Ä‘áº·t nháº¯c nhá»Ÿ
  bool _reminderEnabled = false;
  String _notificationMode = 'sound'; // 'sound', 'vibrate', 'both', 'silent'
  
  // Interval nháº¯c nhá»Ÿ (cÃ³ test options)
  int _reminderIntervalMinutes = 30;
  DateTime? _reminderStartedAt; // Thá»i Ä‘iá»ƒm báº­t nháº¯c nhá»Ÿ
  
  // Options cho interval
  static const List<Map<String, dynamic>> _intervalOptions = [
    {'value': 1, 'label': '30 giÃ¢y (test)', 'seconds': 30},
    {'value': 2, 'label': '1 phÃºt (test)', 'seconds': 60},
    {'value': 15, 'label': '15 phÃºt', 'seconds': 900},
    {'value': 30, 'label': '30 phÃºt', 'seconds': 1800},
    {'value': 45, 'label': '45 phÃºt', 'seconds': 2700},
    {'value': 60, 'label': '60 phÃºt', 'seconds': 3600},
  ];
  
  String _getIntervalLabel(int value) {
    final opt = _intervalOptions.firstWhere(
      (o) => o['value'] == value, 
      orElse: () => {'label': '$value phÃºt'},
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
  
  // Lá»‹ch sá»­ uá»‘ng nÆ°á»›c hÃ´m nay
  final List<Map<String, dynamic>> _todayHistory = [];
  
  // Lá»‹ch sá»­ cÃ¡c ngÃ y trÆ°á»›c (load tá»« SharedPreferences)
  List<Map<String, dynamic>> _weekHistory = [];
  
  /// Táº¡o date key cho SharedPreferences: "2026-03-07"
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

  /// Load weight/height tá»« SharedPreferences (Ä‘á»“ng bá»™ tá»« má»i nguá»“n)
  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final hs = HealthService();
    
    // Æ¯u tiÃªn láº¥y height tá»« health service (user_height_cm)
    double? h = await hs.getHeight();
    // Fallback sang profile_height
    if (h == null) {
      final profileH = prefs.getString('profile_height') ?? '';
      if (profileH.isNotEmpty) h = double.tryParse(profileH);
    }
    
    // Æ¯u tiÃªn láº¥y weight tá»« health service (weight_history)
    double? w = await hs.getLatestWeight();
    // Fallback sang profile_weight
    if (w == null) {
      final profileW = prefs.getString('profile_weight') ?? '';
      if (profileW.isNotEmpty) w = double.tryParse(profileW);
    }
    
    // Náº¿u váº«n thiáº¿u thÃ¬ sync tá»« Firestore profile
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

  /// Load dá»¯ liá»‡u uá»‘ng nÆ°á»›c theo ngÃ y tá»« SharedPreferences, sync tá»« Firestore náº¿u local trá»‘ng
  Future<void> _loadWaterData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey;
    
    // Kiá»ƒm tra ngÃ y má»›i â†’ reset náº¿u cáº§n
    final lastDate = prefs.getString('water_last_date') ?? '';
    if (lastDate != today) {
      // LÆ°u dá»¯ liá»‡u ngÃ y cÅ© vÃ o history trÆ°á»›c khi reset
      if (lastDate.isNotEmpty) {
        final oldMl = prefs.getInt('water_current_ml') ?? 0;
        if (oldMl > 0) {
          await prefs.setInt('water_history_$lastDate', oldMl);
        }
      }
      // Reset cho ngÃ y má»›i
      await prefs.setInt('water_current_ml', 0);
      await prefs.setString('water_last_date', today);
      await prefs.remove('water_today_entries');
    }
    
    // Load dá»¯ liá»‡u hÃ´m nay tá»« local
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

    // Náº¿u local trá»‘ng â†’ sync tá»« Firestore (cÃ i láº¡i app / Ä‘á»•i tÃ i khoáº£n)
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
            // Load entries tá»« Firestore
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
    
    // Load lá»‹ch sá»­ 7 ngÃ y trÆ°á»›c
    final List<Map<String, dynamic>> weekData = [];
    bool hasLocalHistory = false;
    for (int i = 1; i <= 7; i++) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _dateKey(date);
      final amount = prefs.getInt('water_history_$key') ?? 0;
      if (amount > 0) hasLocalHistory = true;
      weekData.add({'date': date, 'amount': amount});
    }
    
    // Náº¿u local history trá»‘ng â†’ sync tá»« Firestore
    if (!hasLocalHistory) {
      try {
        final cloudHistory = await FirestoreService().loadWaterHistory(7);
        if (cloudHistory.isNotEmpty) {
          weekData.clear();
          for (final item in cloudHistory) {
            final date = item['date'] as DateTime;
            final amount = (item['amount'] as num?)?.toInt() ?? 0;
            weekData.add({'date': date, 'amount': amount});
            // Cache láº¡i vÃ o local
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
  
  // LÃªn lá»‹ch notification cho background (khi app Ä‘Ã³ng)
  Future<bool> _scheduleBackgroundNotifications() async {
    if (kIsWeb) return false;
    if (!_reminderEnabled) return false;
    
    try {
      await NotificationService().initialize();

      // YÃªu cáº§u quyá»n notification (Android 13+)
      final notifPermission = await NotificationService().requestPermission();
      if (!notifPermission) {
        debugPrint('âš ï¸ Notification permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vui lÃ²ng cáº¥p quyá»n thÃ´ng bÃ¡o Ä‘á»ƒ nháº­n nháº¯c nhá»Ÿ')),
          );
        }
        return false;
      }
      
      // YÃªu cáº§u quyá»n exact alarm (Android 12+)
      if (!kIsWeb && Platform.isAndroid) {
        final exactAlarmOk = await NotificationService().requestExactAlarmPermission();
        if (!exactAlarmOk) {
          debugPrint('âš ï¸ Exact alarm permission denied');
        }
        
        // Kiá»ƒm tra quyá»n hiá»ƒn thá»‹ trÃªn á»©ng dá»¥ng khÃ¡c
        final canOverlay = await NotificationService().canDrawOverlays();
        final batteryOptimized = await NotificationService().isBatteryOptimized();
        
        if ((!canOverlay || batteryOptimized) && mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cáº§n cáº¥p thÃªm quyá»n'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Äá»ƒ nháº¯c nhá»Ÿ hiá»‡n full mÃ n hÃ¬nh khi khÃ³a mÃ n hÃ¬nh, cáº§n báº­t:'),
                  const SizedBox(height: 12),
                  if (!canOverlay) 
                    const Text('â€¢ Hiá»ƒn thá»‹ trÃªn á»©ng dá»¥ng khÃ¡c'),
                  if (batteryOptimized)
                    const Text('â€¢ Táº¯t tá»‘i Æ°u pin cho BetterME'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Äá»ƒ sau'),
                ),
                if (!canOverlay)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NotificationService().openOverlaySettings();
                    },
                    child: const Text('Cáº¥p quyá»n overlay'),
                  ),
                if (canOverlay && batteryOptimized)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      NotificationService().openBatterySettings();
                    },
                    child: const Text('Táº¯t tá»‘i Æ°u pin'),
                  ),
              ],
            ),
          );
        }
      }
      
      final interval = _getIntervalDuration();
      
      // LÃªn lá»‹ch notification
      final scheduledCount = await NotificationService().schedulePeriodicNotification(
        id: 1,
        title: 'ÄÃ£ Ä‘áº¿n uá»‘ng nÆ°á»›c!',
        body: 'Gá»£i Ã½: ${_suggestedAmountPerDrink}ml. Uá»‘ng ngay!',
        interval: interval,
        payload: 'water_reminder',
      );
      if (scheduledCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('KhÃ´ng lÃªn lá»‹ch Ä‘Æ°á»£c nháº¯c nhá»Ÿ. Vui lÃ²ng kiá»ƒm tra quyá»n thÃ´ng bÃ¡o.'),
            ),
          );
        }
        return false;
      }

      debugPrint('âœ… Background notifications scheduled: $scheduledCount items');
      return true;
    } catch (e) {
      debugPrint('âŒ Error scheduling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lá»—i lÃªn lá»‹ch nháº¯c nhá»Ÿ: $e')),
        );
      }
      return false;
    }
  }
  
  Future<void> _stopBackgroundNotifications() async {
    if (kIsWeb) return;
    await NotificationService().stopWaterReminder();
  }

  /// Cáº­p nháº­t cháº¿ Ä‘á»™ thÃ´ng bÃ¡o + re-schedule notifications ngay
  Future<void> _updateNotificationMode(String mode) async {
    setState(() => _notificationMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('water_notification_mode', mode);
    
    // Re-schedule notifications vá»›i mode má»›i
    if (_reminderEnabled) {
      await _scheduleBackgroundNotifications();
    }
  }

  /// Dialog cho ngÆ°á»i dÃ¹ng chá»n sá»‘ ml khi báº¥m "Uá»‘ng ngay"
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
                'ðŸ’§ Chá»n lÆ°á»£ng nÆ°á»›c báº¡n uá»‘ng',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Gá»£i Ã½: ${_suggestedAmountPerDrink}ml',
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
                child: const Text('Nháº­p sá»‘ khÃ¡c'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  double get _progress => _dailyGoalMl > 0 ? _currentMl / _dailyGoalMl : 0;
  
  // TÃ­nh lÆ°á»£ng nÆ°á»›c gá»£i Ã½ má»—i láº§n uá»‘ng - Tá»° Äá»˜NG ÄIá»€U CHá»ˆNH
  int get _suggestedAmountPerDrink {
    final remaining = _dailyGoalMl - _currentMl;
    if (remaining <= 0) return 200; // ÄÃ£ Ä‘áº¡t má»¥c tiÃªu
    
    // TÃ­nh sá»‘ láº§n nháº¯c cÃ²n láº¡i Ä‘áº¿n 22:00
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 22, 0); // Giáº£ sá»­ ngá»«ng uá»‘ng trÆ°á»›c 22h
    
    if (now.isAfter(endOfDay)) return remaining.clamp(100, 500);
    
    final remainingMinutes = endOfDay.difference(now).inMinutes;
    final intervalMinutes = _getIntervalDuration().inSeconds / 60;
    final remainingReminders = (remainingMinutes / intervalMinutes).floor();
    
    if (remainingReminders <= 0) return remaining.clamp(100, 500);
    
    // Chia Ä‘á»u lÆ°á»£ng nÆ°á»›c cÃ²n láº¡i cho sá»‘ láº§n nháº¯c cÃ²n láº¡i
    final suggested = (remaining / remainingReminders).round();
    return suggested.clamp(100, 500); // Min 100ml, max 500ml má»—i láº§n
  }

  void _addWater(int ml) {
    // Kiá»ƒm tra náº¿u Ä‘Ã£ Ä‘á»§ má»¥c tiÃªu vÃ  chÆ°a há»i
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
    
    // Sync lÃªn SharedPreferences Ä‘á»ƒ HomeScreen Ä‘á»c Ä‘Æ°á»£c
    _syncWaterProgress();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ÄÃ£ uá»‘ng ${ml}ml'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 1),
      ),
    );
    
    // Chá»‰ hiá»ƒn thá»‹ chÃºc má»«ng khi vá»«a Ä‘áº¡t má»¥c tiÃªu
    if (_currentMl >= _dailyGoalMl && _currentMl - ml < _dailyGoalMl) {
      _showCongratulations();
    }
  }
  
  /// Sync tiáº¿n Ä‘á»™ uá»‘ng nÆ°á»›c lÃªn SharedPreferences + Firestore
  Future<void> _syncWaterProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('water_current_ml', _currentMl);
    await prefs.setInt('water_daily_goal_ml', _dailyGoalMl);
    await prefs.setString('water_last_date', _todayKey);
    
    // LÆ°u lá»‹ch sá»­ entries hÃ´m nay
    final entries = _todayHistory.map((e) {
      final time = e['time'] as DateTime;
      return '${time.millisecondsSinceEpoch}|${e['amount']}';
    }).toList();
    await prefs.setStringList('water_today_entries', entries);
    
    // LÆ°u tá»•ng ml hÃ´m nay vÃ o history key
    await prefs.setInt('water_history_$_todayKey', _currentMl);
    
    // Äá»“ng bá»™ lÃªn Firestore
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
        title: const Text('ðŸŽ‰ ÄÃ£ Ä‘á»§ má»¥c tiÃªu!'),
        content: Text(
          'Báº¡n Ä‘Ã£ uá»‘ng Ä‘á»§ ${_dailyGoalMl}ml hÃ´m nay.\n'
          'Báº¡n cÃ³ muá»‘n tiáº¿p tá»¥c uá»‘ng thÃªm khÃ´ng?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KhÃ´ng'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _hasAskedContinue = true;
              });
              _addWater(ml);
            },
            child: const Text('Uá»‘ng tiáº¿p'),
          ),
        ],
      ),
    );
  }

  void _showCongratulations() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ðŸŽ‰ Tuyá»‡t vá»i!'),
        content: const Text(
          'Báº¡n Ä‘Ã£ hoÃ n thÃ nh má»¥c tiÃªu uá»‘ng nÆ°á»›c hÃ´m nay!\n'
          'Tiáº¿p tá»¥c duy trÃ¬ nhÃ©!'
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
        title: const Text('Sá»­a lÆ°á»£ng nÆ°á»›c'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'LÆ°á»£ng nÆ°á»›c (ml)',
                suffixText: 'ml',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thá»i gian: ${_formatTime(entry['time'] as DateTime)}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // XÃ³a entry
              setState(() {
                _currentMl -= entry['amount'] as int;
                _todayHistory.removeAt(index);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ÄÃ£ xÃ³a')),
              );
            },
            child: const Text('XÃ³a', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Há»§y'),
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
                  const SnackBar(content: Text('ÄÃ£ cáº­p nháº­t')),
                );
              }
            },
            child: const Text('LÆ°u'),
          ),
        ],
      ),
    );
  }

  void _resetToday() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Äáº·t láº¡i hÃ´m nay?'),
        content: const Text('Táº¥t cáº£ lá»‹ch sá»­ uá»‘ng nÆ°á»›c hÃ´m nay sáº½ bá»‹ xÃ³a.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Há»§y'),
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
                const SnackBar(content: Text('ÄÃ£ Ä‘áº·t láº¡i')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Äáº·t láº¡i'),
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
      appBar: AppBar(
        title: const Text('Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Uá»‘ng nÆ°á»›c'),
            Tab(text: 'Nháº¯c nhá»Ÿ'),
            Tab(text: 'Lá»‹ch sá»­'),
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

  // Tab 1: Uá»‘ng nÆ°á»›c
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
          
          
          // Chá»n má»¥c tiÃªu
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Má»¥c tiÃªu hÃ´m nay',
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
                    child: const Text('TÃ¹y chá»‰nh'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Quick add buttons
          Text(
            'Chá»n lÆ°á»£ng nÆ°á»›c',
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
            child: const Text('Nháº­p sá»‘ khÃ¡c'),
          ),
          
          const SizedBox(height: 24),
          
          // Today's quick history
          if (_todayHistory.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'HÃ´m nay (${_todayHistory.length} láº§n)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(2),
                  child: const Text('Xem chi tiáº¿t â†’'),
                ),
              ],
            ),
          ],
          
          const SizedBox(height: 16),
          
          // ThÃ´ng tin ngÆ°á»i dÃ¹ng (Ä‘Æ°a xuá»‘ng cuá»‘i)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ThÃ´ng tin cá»§a báº¡n',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: _showEditProfileDialog,
                        child: const Text('Sá»­a'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('CÃ¢n náº·ng: ${_weight.toStringAsFixed(1)} kg'),
                      const SizedBox(width: 24),
                      Text('Chiá»u cao: ${_height.toStringAsFixed(0)} cm'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gá»£i Ã½: ${(_weight * 33).round()}ml/ngÃ y (33ml Ã— cÃ¢n náº·ng)',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
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
            const Text('Gá»£i Ã½', style: TextStyle(fontSize: 9)),
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
        title: const Text('ThÃ´ng tin cÃ¡ nhÃ¢n'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CÃ¢n náº·ng',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Chiá»u cao',
                suffixText: 'cm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Há»§y'),
          ),
          ElevatedButton(
            onPressed: () async {
              final weight = double.tryParse(weightController.text);
              final height = double.tryParse(heightController.text);
              if (weight != null && height != null && weight > 20 && weight < 300 && height > 50 && height < 300) {
                final prefs = await SharedPreferences.getInstance();
                final hs = HealthService();
                
                // LÆ°u vÃ o health service (user_height_cm + weight_history)
                await hs.saveHeight(height);
                await hs.saveWeight(weight);
                
                // Äá»“ng bá»™ sang profile keys
                await prefs.setString('profile_height', height.toStringAsFixed(0));
                await prefs.setString('profile_weight', weight.toStringAsFixed(1));
                
                setState(() {
                  _weight = weight;
                  _height = height;
                });
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('LÆ°u'),
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
        title: const Text('Má»¥c tiÃªu tÃ¹y chá»‰nh'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'LÆ°á»£ng nÆ°á»›c',
            suffixText: 'ml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Há»§y'),
          ),
          ElevatedButton(
            onPressed: () {
              final goal = int.tryParse(controller.text);
              if (goal != null && goal > 0) {
                setState(() => _dailyGoalMl = goal);
                Navigator.pop(context);
              }
            },
            child: const Text('LÆ°u'),
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
        title: const Text('Nháº­p lÆ°á»£ng nÆ°á»›c'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Sá»‘ ml',
            suffixText: 'ml',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Há»§y'),
          ),
          ElevatedButton(
            onPressed: () {
              final ml = int.tryParse(controller.text);
              if (ml != null && ml > 0) {
                Navigator.pop(context);
                _addWater(ml);
              }
            },
            child: const Text('ThÃªm'),
          ),
        ],
      ),
    );
  }

  // Tab 2: Nháº¯c nhá»Ÿ
  Widget _buildRemindersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Báº­t/táº¯t nháº¯c nhá»Ÿ
          Card(
            child: SwitchListTile(
              title: const Text('Nháº¯c nhá»Ÿ uá»‘ng nÆ°á»›c'),
              subtitle: Text(
                _reminderEnabled 
                    ? 'Má»—i ${_getIntervalLabel(_reminderIntervalMinutes)} â€¢ Báº¯t Ä‘áº§u tá»« ${_reminderStartedAt != null ? _formatTime(_reminderStartedAt!) : "bÃ¢y giá»"}'
                    : 'ÄÃ£ táº¯t',
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
                        content: Text('âœ… ÄÃ£ báº­t nháº¯c nhá»Ÿ má»—i ${_getIntervalLabel(_reminderIntervalMinutes)}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else if (!success && mounted) {
                    // Revert toggle náº¿u khÃ´ng lÃªn lá»‹ch Ä‘Æ°á»£c
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
            // Cháº¿ Ä‘á»™ thÃ´ng bÃ¡o
            Text(
              'Cháº¿ Ä‘á»™ thÃ´ng bÃ¡o',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<String>(
                    title: const Text('ChuÃ´ng'),
                    subtitle: const Text('PhÃ¡t Ã¢m thanh khi nháº¯c nhá»Ÿ'),
                    value: 'sound',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Rung'),
                    subtitle: Text(Platform.isIOS
                        ? 'KhÃ´ng Ã¢m thanh (rung theo cÃ i Ä‘áº·t iPhone)'
                        : 'Chá»‰ rung liÃªn tá»¥c, khÃ´ng cÃ³ Ã¢m thanh'),
                    value: 'vibrate',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('ChuÃ´ng + Rung'),
                    subtitle: const Text('Cáº£ Ã¢m thanh vÃ  rung liÃªn tá»¥c'),
                    value: 'both',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Im láº·ng'),
                    subtitle: const Text('Chá»‰ hiá»‡n thÃ´ng bÃ¡o'),
                    value: 'silent',
                    groupValue: _notificationMode,
                    onChanged: (value) => _updateNotificationMode(value!),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Khoáº£ng cÃ¡ch nháº¯c nhá»Ÿ
            Text(
              'Khoáº£ng cÃ¡ch nháº¯c nhá»Ÿ',
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
                        const Text('Nháº¯c má»—i'),
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
            
            // ThÃ´ng tin tá»± Ä‘á»™ng Ä‘iá»u chá»‰nh
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
                          'Tá»± Ä‘á»™ng Ä‘iá»u chá»‰nh',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.water_drop, 'ÄÃ£ uá»‘ng', '$_currentMl / $_dailyGoalMl ml'),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.local_drink, 'CÃ²n láº¡i', '${(_dailyGoalMl - _currentMl).clamp(0, _dailyGoalMl)} ml'),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.recommend, 'Gá»£i Ã½ láº§n tá»›i', '${_suggestedAmountPerDrink} ml'),
                    if (_todayHistory.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _buildInfoRow(Icons.trending_up, 'TB má»—i láº§n', '${(_currentMl / _todayHistory.length).round()} ml'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Gá»£i Ã½ khoa há»c
            Card(
              color: Colors.blue.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gá»£i Ã½ khoa há»c',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'â€¢ LÆ°á»£ng gá»£i Ã½ tá»± Ä‘iá»u chá»‰nh theo lÆ°á»£ng Ä‘Ã£ uá»‘ng\n'
                      'â€¢ Uá»‘ng nhiá»u hÆ¡n â†’ láº§n sau gá»£i Ã½ Ã­t hÆ¡n\n'
                      'â€¢ Uá»‘ng Ã­t hÆ¡n â†’ láº§n sau gá»£i Ã½ nhiá»u hÆ¡n\n'
                      'â€¢ NÃªn uá»‘ng nÆ°á»›c áº¥m vÃ o buá»•i sÃ¡ng\n'
                      'â€¢ TrÃ¡nh uá»‘ng quÃ¡ nhiá»u trÆ°á»›c khi ngá»§',
                      style: TextStyle(color: Colors.grey[700], height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
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

  // Tab 3: Lá»‹ch sá»­
  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lá»‹ch sá»­ hÃ´m nay
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HÃ´m nay',
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
                    'ChÆ°a uá»‘ng nÆ°á»›c hÃ´m nay',
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
                      child: const Text('Sá»­a'),
                    ),
                  );
                },
              ),
            ),
          
          const SizedBox(height: 24),
          
          // Weekly chart
          Text(
            'Tuáº§n nÃ y',
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
            'Thá»‘ng kÃª',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Trung bÃ¬nh',
                  '${_getAverageIntake()}ml',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Streak',
                  '${_getStreak()} ngÃ y',
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
                  'HoÃ n thÃ nh',
                  '${_getCompletedDays()}/7',
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Cao nháº¥t',
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

/// Expense Screen - Quáº£n lÃ½ chi tiÃªu
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

  /// Load giao dá»‹ch tá»« SharedPreferences, rá»“i sync tá»« Firestore
  Future<void> _loadTransactions() async {
    // Load local trÆ°á»›c cho nhanh
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
    
    // Sync tá»« Firestore náº¿u local trá»‘ng
    if (loaded.isEmpty) {
      final cloudData = await FirestoreService().loadTransactions();
      if (cloudData.isNotEmpty && mounted) {
        setState(() {
          _transactions.clear();
          _transactions.addAll(cloudData);
        });
        // LÆ°u láº¡i local
        final localData = _transactions.map((t) {
          final date = t['date'] as DateTime;
          return '${t['type']}|${t['amount']}|${t['category']}|${t['note'] ?? ''}|${date.millisecondsSinceEpoch}';
        }).toList();
        await prefs.setStringList('expense_transactions', localData);
      }
    }
  }

  /// LÆ°u giao dá»‹ch vÃ o SharedPreferences + Firestore
  Future<void> _saveTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _transactions.map((t) {
      final date = t['date'] as DateTime;
      return '${t['type']}|${t['amount']}|${t['category']}|${t['note'] ?? ''}|${date.millisecondsSinceEpoch}';
    }).toList();
    await prefs.setStringList('expense_transactions', data);
    
    // Äá»“ng bá»™ lÃªn Firestore
    FirestoreService().saveTransactions(_transactions);
  }

  void _showAddTransactionDialog({bool isIncome = false}) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String selectedCategory = isIncome ? 'LÆ°Æ¡ng' : 'Ä‚n uá»‘ng';
    
    final incomeCategories = ['LÆ°Æ¡ng', 'ThÆ°á»Ÿng', 'Äáº§u tÆ°', 'KhÃ¡c'];
    final expenseCategories = ['Ä‚n uá»‘ng', 'Di chuyá»ƒn', 'Mua sáº¯m', 'Giáº£i trÃ­', 'HÃ³a Ä‘Æ¡n', 'KhÃ¡c'];
    
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
                    isIncome ? 'ThÃªm thu nháº­p' : 'ThÃªm chi tiÃªu',
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
                  labelText: 'Sá»‘ tiá»n',
                  prefixText: 'Ä‘ ',
                  prefixIcon: Icon(
                    isIncome ? Icons.add_circle : Icons.remove_circle,
                    color: isIncome ? Colors.green : Colors.red,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Category
              Text('Danh má»¥c', style: Theme.of(context).textTheme.titleSmall),
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
                  labelText: 'Ghi chÃº (tÃ¹y chá»n)',
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
                                ? 'ÄÃ£ thÃªm thu nháº­p ${_formatCurrency(amount)}'
                                : 'ÄÃ£ thÃªm chi tiÃªu ${_formatCurrency(amount)}',
                          ),
                          backgroundColor: isIncome ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIncome ? Colors.green : Colors.red,
                  ),
                  child: const Text('LÆ°u'),
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
    return '${amount.toStringAsFixed(0)}Ä‘';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quáº£n lÃ½ chi tiÃªu'),
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
                  'Sá»‘ dÆ°',
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
                      'Thu nháº­p',
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
                      'Chi tiÃªu',
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
                    label: const Text('Thu nháº­p'),
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
                    label: const Text('Chi tiÃªu'),
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
                          'ChÆ°a cÃ³ giao dá»‹ch nÃ o',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Báº¥m nÃºt trÃªn Ä‘á»ƒ thÃªm thu nháº­p/chi tiÃªu',
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
                            const SnackBar(content: Text('ÄÃ£ xÃ³a giao dá»‹ch')),
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

