import '../models/habit_model.dart';
import '../models/habit_log_model.dart';

/// Habit Repository Interface
/// Định nghĩa các phương thức để tương tác với data source
abstract class HabitRepository {
  /// Lấy tất cả habits của user
  Future<List<HabitModel>> getAllHabits();

  /// Lấy habit theo ID
  Future<HabitModel?> getHabitById(String id);

  /// Tạo habit mới
  Future<HabitModel> createHabit(HabitModel habit);

  /// Cập nhật habit
  Future<HabitModel> updateHabit(HabitModel habit);

  /// Xóa habit
  Future<void> deleteHabit(String id);

  /// Ghi log hoàn thành
  Future<HabitLogModel> logCompletion(String habitId, {String? note});

  /// Lấy logs theo ngày
  Future<List<HabitLogModel>> getLogsByDate(DateTime date);

  /// Lấy logs theo habit
  Future<List<HabitLogModel>> getLogsByHabit(String habitId);

  /// Kiểm tra habit đã hoàn thành hôm nay chưa
  Future<bool> isCompletedToday(String habitId);

  /// Lấy streak hiện tại
  Future<int> getCurrentStreak(String habitId);
}
