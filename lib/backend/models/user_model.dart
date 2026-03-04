/// User Model
class UserModel {
  final String id;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final DateTime createdAt;
  final Map<String, dynamic>? settings;

  UserModel({
    required this.id,
    this.email,
    this.displayName,
    this.photoUrl,
    required this.createdAt,
    this.settings,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      settings: json['settings'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'createdAt': createdAt.toIso8601String(),
      'settings': settings,
    };
  }
}
