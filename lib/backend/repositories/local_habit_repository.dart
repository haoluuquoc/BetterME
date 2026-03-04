import 'package:uuid/uuid.dart';
import '../models/habit_model.dart';
import '../models/habit_log_model.dart';
import 'habit_repository.dart';

/// Local implementation of HabitRepository
/// Sử dụng in-memory storage (sau này sẽ thay bằng Hive/SQLite)
class LocalHabitRepository implements HabitRepository {
  final List<HabitModel> _habits = [];
  final List<HabitLogModel> _logs = [];
  final _uuid = const Uuid();

  @override
  Future<List<HabitModel>> getAllHabits() async {
    return List.unmodifiable(_habits);
  }

  @override
  Future<HabitModel?> getHabitById(String id) async {
    try {
      return _habits.firstWhere((h) => h.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<HabitModel> createHabit(HabitModel habit) async {
    final newHabit = habit.copyWith(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
    );
    _habits.add(newHabit);
    return newHabit;
  }

  @override
  Future<HabitModel> updateHabit(HabitModel habit) async {
    final index = _habits.indexWhere((h) => h.id == habit.id);
    if (index == -1) throw Exception('Habit not found');
    
    final updated = habit.copyWith(updatedAt: DateTime.now());
    _habits[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteHabit(String id) async {
    _habits.removeWhere((h) => h.id == id);
    _logs.removeWhere((l) => l.habitId == id);
  }

  @override
  Future<HabitLogModel> logCompletion(String habitId, {String? note}) async {
    final log = HabitLogModel(
      id: _uuid.v4(),
      habitId: habitId,
      completedAt: DateTime.now(),
      note: note,
    );
    _logs.add(log);
    return log;
  }

  @override
  Future<List<HabitLogModel>> getLogsByDate(DateTime date) async {
    return _logs.where((l) => 
      l.completedAt.year == date.year &&
      l.completedAt.month == date.month &&
      l.completedAt.day == date.day
    ).toList();
  }

  @override
  Future<List<HabitLogModel>> getLogsByHabit(String habitId) async {
    return _logs.where((l) => l.habitId == habitId).toList();
  }

  @override
  Future<bool> isCompletedToday(String habitId) async {
    final today = DateTime.now();
    return _logs.any((l) =>
      l.habitId == habitId &&
      l.completedAt.year == today.year &&
      l.completedAt.month == today.month &&
      l.completedAt.day == today.day
    );
  }

  @override
  Future<int> getCurrentStreak(String habitId) async {
    final logs = await getLogsByHabit(habitId);
    if (logs.isEmpty) return 0;

    logs.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    
    int streak = 0;
    DateTime checkDate = DateTime.now();
    
    for (var log in logs) {
      if (_isSameDay(log.completedAt, checkDate)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else if (log.completedAt.isBefore(checkDate)) {
        break;
      }
    }
    
    return streak;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
