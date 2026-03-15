import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_colors.dart';
import '../../services/health_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'step_history_screen.dart';

/// Màn hình Sức khỏe — bước chân, giấc ngủ, cân nặng, sinh nhật
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _healthService = HealthService();

  // Steps
  int _todaySteps = 0;
  StreamSubscription<int>? _stepsSub;

  // Sleep & Weight
  double? _todaySleep;
  double? _latestWeight;
  double? _heightCm;

  // Birthday
  List<Map<String, String>> _birthdays = [];
  List<String> _todayBirthdays = [];

  // History
  List<Map<String, dynamic>> _stepHistory = [];
  List<Map<String, dynamic>> _sleepHistory = [];
  List<Map<String, dynamic>> _weightHistory = [];
  bool _refreshingSteps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    await _healthService.init();
    _todaySteps = _healthService.todaySteps;
    await _stepsSub?.cancel();
    _stepsSub = _healthService.stepsStream.listen((steps) {
      if (mounted) setState(() => _todaySteps = steps);
    });
    await _healthService.refreshStepsFromHealth(requestPermission: false);
    await _loadAllData();
  }

  Future<void> _refreshSteps() async {
    if (_refreshingSteps) return;
    setState(() => _refreshingSteps = true);
    final result =
        await _healthService.refreshStepsFromHealth(requestPermission: true);
    if (mounted) {
      setState(() {
        _refreshingSteps = false;
        _todaySteps = _healthService.todaySteps;
      });
      await _loadAllData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_stepsRefreshMessage(result.status)),
        ),
      );
    }
  }

  Future<void> _loadAllData() async {
    final sleep = await _healthService.getTodaySleep();
    final weight = await _healthService.getLatestWeight();
    final height = await _healthService.getHeight();
    final birthdays = await _healthService.getBirthdays();
    final todayBdays = await _healthService.getTodayBirthdays();
    final stepHist = await _healthService.getStepHistory();
    final sleepHist = await _healthService.getSleepHistory();
    final weightHist = await _healthService.getWeightHistory(days: 10);

    if (mounted) {
      setState(() {
        _todaySleep = sleep;
        _latestWeight = weight;
        _heightCm = height;
        _birthdays = birthdays;
        _todayBirthdays = todayBdays;
        _stepHistory = stepHist;
        _sleepHistory = sleepHist;
        _weightHistory = weightHist;
      });
    }
  }

  @override
  void dispose() {
    _stepsSub?.cancel();
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Lưu steps khi app chuyển sang background
      _healthService.saveTodayStepsToHistory();
    } else if (state == AppLifecycleState.resumed) {
      // Re-init để lấy lại permission nếu user vừa cấp trong Settings
      _initData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sức khỏe'),
        actions: [
          IconButton(
            onPressed: _refreshingSteps ? null : _refreshSteps,
            icon: _refreshingSteps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Làm mới bước chân',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Hôm nay'),
            Tab(text: 'Lịch sử'),
            Tab(text: 'Sinh nhật'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTodayTab(theme),
          _buildHistoryTab(theme),
          _buildBirthdayTab(theme),
        ],
      ),
    );
  }

  // ==================== TAB 1: HÔm nay ====================

  Widget _buildTodayTab(ThemeData theme) {
    final distanceStr = _healthService.formatDistance(_todaySteps);
    final calories = _healthService.getCalories(_todaySteps);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Birthday banner
          if (_todayBirthdays.isNotEmpty) ...[
            _buildBirthdayBanner(theme),
            const SizedBox(height: 16),
          ],

          // Today Activity card
          _buildActivityCard(theme, distanceStr, calories),
          const SizedBox(height: 16),

          // Sleep + Weight row
          Row(
            children: [
              Expanded(child: _buildSleepCard(theme)),
              const SizedBox(width: 12),
              Expanded(child: _buildWeightCard(theme)),
            ],
          ),
          const SizedBox(height: 12),

          // Height + BMI card
          _buildHeightBmiCard(theme),
          const SizedBox(height: 16),

          // Health recommendations
          _buildRecommendationsCard(theme),
        ],
      ),
    );
  }

  Widget _buildBirthdayBanner(ThemeData theme) {
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
              _todayBirthdays.length == 1
                  ? 'Hôm nay là sinh nhật $names 🎉'
                  : 'Hôm nay là sinh nhật $names 🎉',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.pink.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(
      ThemeData theme, String distanceStr, double calories) {
    return Card(
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
                    color: Colors.deepOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.directions_walk,
                      color: Colors.deepOrange, size: 26),
                ),
                const SizedBox(width: 14),
                Text(
                  'Hoạt động hôm nay',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Steps big number
            Center(
              child: Column(
                children: [
                  Text(
                    NumberFormat('#,###').format(_todaySteps),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'bước chân',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Distance + Calories row
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    theme,
                    Icons.straighten,
                    distanceStr,
                    'Quãng đường',
                    Colors.teal,
                  ),
                ),
                Container(
                  height: 40,
                  width: 1,
                  color: theme.dividerColor,
                ),
                Expanded(
                  child: _buildStatTile(
                    theme,
                    Icons.local_fire_department,
                    '${calories.toStringAsFixed(0)} kcal',
                    'Calories',
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(
      ThemeData theme, IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.grey),
        ),
      ],
    );
  }

  Widget _buildSleepCard(ThemeData theme) {
    final sleepLabel = _healthService.sleepLabel(_todaySleep);
    final sleepStatus = _healthService.sleepAssessment(_todaySleep);
    final statusColor = sleepStatus == 'good'
        ? Colors.green
        : sleepStatus == 'warning'
            ? Colors.orange
            : sleepStatus == 'bad'
                ? Colors.red
                : Colors.indigo;

    return GestureDetector(
      onTap: _showSleepDialog,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _todaySleep != null
                    ? '${_todaySleep!.toStringAsFixed(1)}h'
                    : '--',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Giấc ngủ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey,
                ),
              ),
              if (sleepLabel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  sleepLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  'Nhấn để ghi',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeightCard(ThemeData theme) {
    final bmi = _healthService.calculateBMI(_latestWeight, _heightCm);
    final bmiText = bmi != null
        ? 'BMI: ${bmi.toStringAsFixed(1)}'
        : null;
    final bmiStatus = bmi != null ? _healthService.bmiStatus(bmi) : null;
    final bmiColor = bmiStatus == 'good'
        ? Colors.green
        : bmiStatus == 'warning'
            ? Colors.orange
            : bmiStatus == 'bad'
                ? Colors.red
                : Colors.teal;

    return GestureDetector(
      onTap: _showWeightDialog,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _latestWeight != null
                    ? '${_latestWeight!.toStringAsFixed(1)}'
                    : '--',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cân nặng (kg)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey,
                ),
              ),
              if (bmiText != null) ...[
                const SizedBox(height: 6),
                Text(
                  bmiText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: bmiColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  _latestWeight != null ? 'Nhập chiều cao' : 'Nhấn để ghi',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TAB 2: LỊCH SỬ ====================

  Widget _buildHeightBmiCard(ThemeData theme) {
    final bmi = _healthService.calculateBMI(_latestWeight, _heightCm);
    final bmiCategory = bmi != null ? _healthService.bmiCategory(bmi) : null;
    final bmiStatus = bmi != null ? _healthService.bmiStatus(bmi) : null;
    final bmiColor = bmiStatus == 'good'
        ? Colors.green
        : bmiStatus == 'warning'
            ? Colors.orange
            : bmiStatus == 'bad'
                ? Colors.red
                : AppColors.grey;

    return GestureDetector(
      onTap: _showHeightDialog,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _heightCm != null
                          ? 'Chiều cao: ${_heightCm!.toStringAsFixed(0)} cm'
                          : 'Nhập chiều cao',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (bmi != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'BMI: ${bmi.toStringAsFixed(1)} — ',
                            style: theme.textTheme.bodySmall,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: bmiColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              bmiCategory!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: bmiColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        'Nhấn để nhập chiều cao & tính BMI',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationsCard(ThemeData theme) {
    final tips = _healthService.getRecommendations(
      sleepHours: _todaySleep,
      weightKg: _latestWeight,
      heightCm: _heightCm,
      steps: _todaySteps,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lời khuyên sức khỏe',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            ...tips.map((tip) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    tip,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 2: LỊCH SỬ ====================

  Widget _buildHistoryTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StepHistoryScreen()),
            ),
            child: _buildHistorySection(
              theme,
              title: 'Bước chân',
              icon: Icons.directions_walk,
              color: Colors.deepOrange,
              items: _stepHistory,
              valueBuilder: (item) =>
                  '${NumberFormat('#,###').format(item['steps'])} bước',
              showChevron: true,
            ),
          ),
          const SizedBox(height: 20),
          _buildHistorySection(
            theme,
            title: 'Giấc ngủ',
            icon: Icons.bedtime,
            color: Colors.indigo,
            items: _sleepHistory,
            valueBuilder: (item) =>
                '${(item['hours'] as double).toStringAsFixed(1)} giờ',
          ),
          const SizedBox(height: 20),
          _buildHistorySection(
            theme,
            title: 'Cân nặng',
            icon: Icons.monitor_weight,
            color: Colors.teal,
            items: _weightHistory,
            valueBuilder: (item) =>
                '${(item['weight'] as double).toStringAsFixed(1)} kg',
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) valueBuilder,
    bool showChevron = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (showChevron)
                  const Icon(Icons.chevron_right, color: AppColors.grey, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Chưa có dữ liệu',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.grey,
                  ),
                ),
              )
            else
              ...items.map((item) {
                final date = _formatDate(item['date'] as String);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(date,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.grey)),
                      Text(
                        valueBuilder(item),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 3: SINH NHẬT ====================

  Widget _buildBirthdayTab(ThemeData theme) {
    return Column(
      children: [
        Expanded(
          child: _birthdays.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🎂', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text(
                        'Chưa có sinh nhật nào',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Thêm sinh nhật bạn bè để được nhắc',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _birthdays.length,
                  itemBuilder: (ctx, i) {
                    final b = _birthdays[i];
                    final isToday =
                        _todayBirthdays.contains(b['name']);
                    return Card(
                      elevation: 0,
                      color: isToday
                          ? Colors.pink.shade50
                          : null,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isToday
                              ? Colors.pink.shade100
                              : AppColors.primary.withOpacity(0.1),
                          child: Text(
                            isToday ? '🎉' : '🎂',
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                        title: Text(
                          b['name'] ?? '',
                          style: TextStyle(
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(b['date'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.grey, size: 20),
                          onPressed: () => _removeBirthday(i),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Thêm sinh nhật'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _showAddBirthdayDialog,
            ),
          ),
        ),
      ],
    );
  }

  // ==================== DIALOGS ====================

  void _showSleepDialog() {
    final controller = TextEditingController(
      text: _todaySleep?.toStringAsFixed(1) ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi giấc ngủ'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Số giờ ngủ',
            hintText: 'VD: 7.5',
            suffixText: 'giờ',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final hours = double.tryParse(controller.text.trim());
              if (hours != null && hours > 0 && hours <= 24) {
                _healthService.saveSleepHours(hours);
                setState(() => _todaySleep = hours);
                _loadAllData();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showWeightDialog() {
    final controller = TextEditingController(
      text: _latestWeight?.toStringAsFixed(1) ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ghi cân nặng'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Cân nặng',
            hintText: 'VD: 65.0',
            suffixText: 'kg',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final kg = double.tryParse(controller.text.trim());
              if (kg != null && kg > 20 && kg < 300) {
                _healthService.saveWeight(kg);
                // Đồng bộ sang profile key
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('profile_weight', kg.toStringAsFixed(1));
                setState(() => _latestWeight = kg);
                _loadAllData();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showHeightDialog() {
    final controller = TextEditingController(
      text: _heightCm?.toStringAsFixed(0) ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chiều cao'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Chiều cao',
            hintText: 'VD: 170',
            suffixText: 'cm',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cm = double.tryParse(controller.text.trim());
              if (cm != null && cm > 50 && cm < 300) {
                _healthService.saveHeight(cm);
                // Đồng bộ sang profile key
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('profile_height', cm.toStringAsFixed(0));
                setState(() => _heightCm = cm);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showAddBirthdayDialog() {
    final nameCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('🎂', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            const Text('Thêm sinh nhật'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên',
                hintText: 'VD: Minh',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(
                labelText: 'Ngày sinh (dd/MM)',
                hintText: 'VD: 12/08',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final date = dateCtrl.text.trim();
              if (name.isNotEmpty && _isValidBirthdayDate(date)) {
                _healthService.addBirthday(name, date);
                _loadAllData();
                Navigator.pop(ctx);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  bool _isValidBirthdayDate(String date) {
    final parts = date.split('/');
    if (parts.length != 2) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (day == null || month == null) return false;
    return day >= 1 && day <= 31 && month >= 1 && month <= 12;
  }

  void _removeBirthday(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa sinh nhật?'),
        content: Text('Xóa sinh nhật của ${_birthdays[index]['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _healthService.removeBirthday(index);
      _loadAllData();
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _stepsRefreshMessage(StepsRefreshStatus status) {
    switch (status) {
      case StepsRefreshStatus.success:
        return 'Đã cập nhật bước chân';
      case StepsRefreshStatus.permissionDenied:
        return 'Chưa cấp quyền đọc bước chân trong Health/Health Connect';
      case StepsRefreshStatus.noData:
        return 'Chưa có dữ liệu bước chân hôm nay';
      case StepsRefreshStatus.error:
        return 'Không đọc được dữ liệu bước chân';
    }
  }
}
