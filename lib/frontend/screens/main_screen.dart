import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'habits_screen.dart';
import 'statistics_screen.dart';
import 'settings_screen.dart';
import '../widgets/bottom_nav_bar.dart';

/// Main Screen - Container cho bottom navigation
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeContent(),
    const HabitsContent(),
    const StatisticsContent(),
    const SettingsContent(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButton: _currentIndex == 0 || _currentIndex == 1
          ? FloatingActionButton(
              onPressed: () {
                _showAddHabitDialog();
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }

  void _showAddHabitDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const AddHabitSheet(),
    );
  }
}

/// Add Habit Bottom Sheet
class AddHabitSheet extends StatefulWidget {
  const AddHabitSheet({super.key});

  @override
  State<AddHabitSheet> createState() => _AddHabitSheetState();
}

class _AddHabitSheetState extends State<AddHabitSheet> {
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
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Thêm thói quen mới',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Icon selector
          Text(
            'Chọn biểu tượng',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _icons.map((icon) => GestureDetector(
              onTap: () => setState(() => _selectedIcon = icon),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _selectedIcon == icon
                      ? Theme.of(context).primaryColor.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: _selectedIcon == icon
                      ? Border.all(color: Theme.of(context).primaryColor, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 24)),
                ),
              ),
            )).toList(),
          ),
          
          const SizedBox(height: 24),

          // Name input
          Text(
            'Tên thói quen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: Chạy bộ mỗi sáng',
            ),
          ),

          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                if (_nameController.text.isNotEmpty) {
                  // TODO: Save habit
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã thêm: $_selectedIcon ${_nameController.text}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập tên thói quen'),
                      backgroundColor: Colors.red,
                    ),
                  );
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
