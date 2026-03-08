import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/theme/app_colors.dart';
import '../../services/health_service.dart';

/// Màn hình lịch sử bước chân với biểu đồ cột — tuần / tháng / năm
class StepHistoryScreen extends StatefulWidget {
  const StepHistoryScreen({super.key});

  @override
  State<StepHistoryScreen> createState() => _StepHistoryScreenState();
}

class _StepHistoryScreenState extends State<StepHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _healthService = HealthService();

  List<Map<String, dynamic>> _weekData = [];
  List<Map<String, dynamic>> _monthData = [];
  List<Map<String, dynamic>> _yearData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final week = await _healthService.getStepHistory(days: 7);
    final month = await _healthService.getStepHistory(days: 30);
    final year = await _healthService.getStepHistory(days: 365);

    if (mounted) {
      setState(() {
        _weekData = week.reversed.toList();
        _monthData = month.reversed.toList();
        _yearData = _aggregateByMonth(year);
      });
    }
  }

  /// Gom dữ liệu theo tháng cho view năm
  List<Map<String, dynamic>> _aggregateByMonth(List<Map<String, dynamic>> data) {
    final map = <String, int>{};
    for (final item in data) {
      final dateStr = item['date'] as String;
      try {
        final date = DateTime.parse(dateStr);
        final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        map[monthKey] = (map[monthKey] ?? 0) + (item['steps'] as int);
      } catch (_) {}
    }

    final sorted = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => {'date': e.key, 'steps': e.value})
        .toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử bước chân'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tuần'),
            Tab(text: 'Tháng'),
            Tab(text: 'Năm'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChartView(_weekData, _ChartMode.week),
          _buildChartView(_monthData, _ChartMode.month),
          _buildChartView(_yearData, _ChartMode.year),
        ],
      ),
    );
  }

  Widget _buildChartView(List<Map<String, dynamic>> data, _ChartMode mode) {
    if (data.isEmpty) {
      return Center(
        child: Text(
          'Chưa có dữ liệu',
          style: TextStyle(color: AppColors.grey),
        ),
      );
    }

    final totalSteps = data.fold<int>(0, (sum, e) => sum + (e['steps'] as int));
    final avgSteps = data.isNotEmpty ? (totalSteps / data.length).round() : 0;
    final maxSteps = data.fold<int>(0, (m, e) => max(m, e['steps'] as int));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Tổng',
                  NumberFormat('#,###').format(totalSteps),
                  'bước',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  mode == _ChartMode.year ? 'TB/tháng' : 'TB/ngày',
                  NumberFormat('#,###').format(avgSteps),
                  'bước',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Cao nhất',
                  NumberFormat('#,###').format(maxSteps),
                  'bước',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Bar chart
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode == _ChartMode.week
                        ? '7 ngày gần đây'
                        : mode == _ChartMode.month
                            ? '30 ngày gần đây'
                            : 'Theo tháng',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: _BarChart(
                      data: data,
                      mode: mode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Detail list
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chi tiết',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...data.reversed.map((item) {
                    final label = _formatLabel(item['date'] as String, mode);
                    final steps = item['steps'] as int;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.grey)),
                          Text(
                            '${NumberFormat('#,###').format(steps)} bước',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepOrange,
                                    ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, String unit) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange,
                    )),
            Text(unit,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.grey)),
          ],
        ),
      ),
    );
  }

  String _formatLabel(String dateStr, _ChartMode mode) {
    if (mode == _ChartMode.year) {
      // dateStr = "2026-03"
      try {
        final parts = dateStr.split('-');
        return 'T${int.parse(parts[1])}/${parts[0]}';
      } catch (_) {
        return dateStr;
      }
    }
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM').format(date);
    } catch (_) {
      return dateStr;
    }
  }
}

enum _ChartMode { week, month, year }

/// Simple bar chart widget (no external dependency)
class _BarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final _ChartMode mode;

  const _BarChart({required this.data, required this.mode});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox();

    final maxVal = data.fold<int>(0, (m, e) => max(m, e['steps'] as int));
    final effectiveMax = maxVal == 0 ? 1 : maxVal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = mode == _ChartMode.month
            ? max(4.0, (constraints.maxWidth - 16) / data.length - 2)
            : max(8.0, (constraints.maxWidth - 16) / data.length - 4);
        final gap = mode == _ChartMode.month ? 2.0 : 4.0;

        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: data.map((item) {
                  final steps = item['steps'] as int;
                  final fraction = steps / effectiveMax;
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: Tooltip(
                      message: '${NumberFormat('#,###').format(steps)} bước',
                      child: Container(
                        width: barWidth,
                        height: max(2, fraction * (constraints.maxHeight - 20)),
                        decoration: BoxDecoration(
                          color: steps >= 10000
                              ? Colors.green
                              : steps >= 5000
                                  ? Colors.deepOrange
                                  : Colors.deepOrange.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(
                              barWidth > 6 ? 4 : 2),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            // X-axis labels — show only a few
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _buildXLabels(context),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildXLabels(BuildContext context) {
    if (data.isEmpty) return [];

    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: AppColors.grey, fontSize: 10);

    if (data.length <= 7) {
      return data.map((item) {
        final dateStr = item['date'] as String;
        String label;
        if (mode == _ChartMode.year) {
          final parts = dateStr.split('-');
          label = 'T${int.parse(parts[1])}';
        } else {
          try {
            final date = DateTime.parse(dateStr);
            label = DateFormat('dd/MM').format(date);
          } catch (_) {
            label = dateStr;
          }
        }
        return Text(label, style: style);
      }).toList();
    }

    // Show first, middle, last for longer data
    String labelOf(int idx) {
      final dateStr = data[idx]['date'] as String;
      if (mode == _ChartMode.year) {
        final parts = dateStr.split('-');
        return 'T${int.parse(parts[1])}/${parts[0].substring(2)}';
      }
      try {
        final date = DateTime.parse(dateStr);
        return DateFormat('dd/MM').format(date);
      } catch (_) {
        return dateStr;
      }
    }

    return [
      Text(labelOf(0), style: style),
      Text(labelOf(data.length ~/ 2), style: style),
      Text(labelOf(data.length - 1), style: style),
    ];
  }
}
