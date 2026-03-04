import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../widgets/bottom_nav_bar.dart';

/// Statistics Screen - Thống kê và báo cáo
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const StatisticsContent(),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 2,
        onTap: (index) => _navigateToScreen(index),
      ),
    );
  }

  void _navigateToScreen(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, Routes.home);
        break;
      case 1:
        Navigator.pushReplacementNamed(context, Routes.habits);
        break;
      case 2:
        // Already on statistics
        break;
      case 3:
        Navigator.pushReplacementNamed(context, Routes.settings);
        break;
    }
  }
}

/// Statistics Content
class StatisticsContent extends StatelessWidget {
  const StatisticsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overview Cards
          Row(
            children: [
              Expanded(child: _buildStatCard(context, 'Tổng streak', '45', Icons.local_fire_department, Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Hoàn thành', '78%', Icons.check_circle, AppColors.success)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard(context, 'Thói quen', '7', Icons.list_alt, AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, 'Ngày hoạt động', '30', Icons.calendar_today, AppColors.accent)),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Weekly Progress
          Text('Tiến độ tuần này', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildWeeklyChart(context),
          
          const SizedBox(height: 24),
          
          // Top habits
          Text('Thói quen tốt nhất', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _buildTopHabit(context, '💧', 'Uống nước', 21, 1),
          _buildTopHabit(context, '📚', 'Đọc sách', 14, 2),
          _buildTopHabit(context, '✍️', 'Viết nhật ký', 10, 3),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context) {
    final days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final values = [0.8, 0.6, 1.0, 0.4, 0.9, 0.7, 0.5];
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (index) => Column(
            children: [
              Container(
                width: 32,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 32,
                    height: 100 * values[index],
                    decoration: BoxDecoration(
                      color: values[index] == 1.0 ? AppColors.success : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(days[index], style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
        ),
      ),
    );
  }

  Widget _buildTopHabit(BuildContext context, String icon, String name, int streak, int rank) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey[300] : Colors.brown[200]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.bold))),
        ),
        title: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(name),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 20),
            const SizedBox(width: 4),
            Text('$streak ngày', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
