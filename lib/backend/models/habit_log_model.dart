/// Habit Log Model - Ghi lại việc hoàn thành habit
class HabitLogModel {
  final String id;
  final String habitId;
  final DateTime completedAt;
  final String? note;

  HabitLogModel({
    required this.id,
    required this.habitId,
    required this.completedAt,
    this.note,
  });

  factory HabitLogModel.fromJson(Map<String, dynamic> json) {
    return HabitLogModel(
      id: json['id'] as String,
      habitId: json['habitId'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'habitId': habitId,
      'completedAt': completedAt.toIso8601String(),
      'note': note,
    };
  }
}
