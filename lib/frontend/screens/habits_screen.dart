import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/habit_card.dart';

/// Habits Screen - Quản lý tất cả habits
class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thói quen'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lọc - Đang phát triển')),
              );
            },
          ),
        ],
      ),
      body: const HabitsContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddHabitDialog();
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
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
        // Already on habits
        break;
      case 2:
        Navigator.pushReplacementNamed(context, Routes.statistics);
        break;
      case 3:
        Navigator.pushReplacementNamed(context, Routes.settings);
        break;
    }
  }

  void _showAddHabitDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _AddHabitSheet(),
    );
  }
}

/// Habits Content - Nội dung trang habits
class HabitsContent extends StatefulWidget {
  const HabitsContent({super.key});

  @override
  State<HabitsContent> createState() => _HabitsContentState();
}

class _HabitsContentState extends State<HabitsContent> {
  List<Map<String, dynamic>> _habits = [
    {'icon': '🏃', 'name': 'Chạy bộ', 'streak': 7, 'completed': true, 'category': 'Sức khỏe'},
    {'icon': '📚', 'name': 'Đọc sách', 'streak': 14, 'completed': false, 'category': 'Học tập'},
    {'icon': '🧘', 'name': 'Thiền', 'streak': 3, 'completed': false, 'category': 'Tinh thần'},
    {'icon': '💧', 'name': 'Uống nước', 'streak': 21, 'completed': true, 'category': 'Sức khỏe'},
    {'icon': '😴', 'name': 'Ngủ đúng giờ', 'streak': 5, 'completed': false, 'category': 'Sức khỏe'},
    {'icon': '✍️', 'name': 'Viết nhật ký', 'streak': 10, 'completed': false, 'category': 'Tinh thần'},
    {'icon': '🍎', 'name': 'Ăn rau củ', 'streak': 8, 'completed': true, 'category': 'Sức khỏe'},
  ];

  void _toggleHabitCompletion(int index) {
    setState(() {
      _habits[index]['completed'] = !(_habits[index]['completed'] as bool);
    });
  }

  void _deleteHabit(int index) {
    final habit = _habits[index];
    setState(() {
      _habits.removeAt(index);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xóa: ${habit['icon']} ${habit['name']}'),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () {
            setState(() {
              _habits.insert(index, habit);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _habits.length,
      itemBuilder: (context, index) {
        final habit = _habits[index];
        return Dismissible(
          key: Key(habit['name'] + index.toString()),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _deleteHabit(index),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: HabitCard(
              icon: habit['icon'] as String,
              name: habit['name'] as String,
              streak: habit['streak'] as int,
              isCompleted: habit['completed'] as bool,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${habit['icon']} ${habit['name']}\n'
                      'Danh mục: ${habit['category']}\n'
                      'Streak: ${habit['streak']} ngày',
                    ),
                  ),
                );
              },
              onComplete: () => _toggleHabitCompletion(index),
            ),
          ),
        );
      },
    );
  }
}

/// Add Habit Sheet
class _AddHabitSheet extends StatefulWidget {
  const _AddHabitSheet();

  @override
  State<_AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<_AddHabitSheet> {
  final _nameController = TextEditingController();
  String _selectedIcon = '⭐';
  
  final List<String> _icons = [
    '⭐', '🏃', '📚', '🧘', '💧', '😴', '🍎', '💪', 
    '🎯', '✍️', '🎨', '🎵', '🌱', '☀️', '🧠', '❤️'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Thêm thói quen mới', style: Theme.of(context).textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Chọn biểu tượng', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _icons.map((icon) => GestureDetector(
              onTap: () => setState(() => _selectedIcon = icon),
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _selectedIcon == icon
                      ? Theme.of(context).primaryColor.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: _selectedIcon == icon
                      ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 24))),
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),
          Text('Tên thói quen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'Ví dụ: Chạy bộ mỗi sáng')),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Đã thêm: $_selectedIcon ${_nameController.text}'), backgroundColor: Colors.green),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Thêm thói quen'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
