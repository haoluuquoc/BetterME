import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Habit Card Widget - Card hiển thị một habit
class HabitCard extends StatelessWidget {
  final String icon;
  final String name;
  final int streak;
  final bool isCompleted;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  const HabitCard({
    super.key,
    required this.icon,
    required this.name,
    required this.streak,
    required this.isCompleted,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCompleted 
                      ? AppColors.success.withOpacity(0.1) 
                      : AppColors.primaryLight.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Name and streak
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        decoration: isCompleted 
                            ? TextDecoration.lineThrough 
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak ngày liên tiếp',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Complete button
              GestureDetector(
                onTap: onComplete,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCompleted 
                        ? AppColors.success 
                        : Colors.transparent,
                    border: Border.all(
                      color: isCompleted 
                          ? AppColors.success 
                          : AppColors.grey,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: isCompleted
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
