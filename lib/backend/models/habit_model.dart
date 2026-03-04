/// Habit Model - Data Transfer Object
/// Đại diện cho dữ liệu habit từ database
class HabitModel {
  final String id;
  final String name;
  final String? description;
  final String icon;
  final String color;
  final int targetDays;
  final List<String> reminderTimes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  HabitModel({
    required this.id,
    required this.name,
    this.description,
    required this.icon,
    required this.color,
    required this.targetDays,
    required this.reminderTimes,
    required this.createdAt,
    this.updatedAt,
  });

  /// From JSON (Firebase/API)
  factory HabitModel.fromJson(Map<String, dynamic> json) {
    return HabitModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String? ?? '⭐',
      color: json['color'] as String? ?? '#0077B6',
      targetDays: json['targetDays'] as int? ?? 7,
      reminderTimes: List<String>.from(json['reminderTimes'] ?? []),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String) 
          : null,
    );
  }

  /// To JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
      'targetDays': targetDays,
      'reminderTimes': reminderTimes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Copy with
  HabitModel copyWith({
    String? id,
    String? name,
    String? description,
    String? icon,
    String? color,
    int? targetDays,
    List<String>? reminderTimes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HabitModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      targetDays: targetDays ?? this.targetDays,
      reminderTimes: reminderTimes ?? this.reminderTimes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
