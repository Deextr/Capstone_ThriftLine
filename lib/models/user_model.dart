import 'base_model.dart';
import 'enums.dart';

class UserModel extends BaseModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.bio,
    this.location,
    required this.role,
    required this.createdAt,
    this.isVerified = false,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? bio;
  final String? location;
  final UserRole role;
  final DateTime createdAt;
  final bool isVerified;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        bio: json['bio'] as String?,
        location: json['location'] as String?,
        role: UserRole.fromString(json['role'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isVerified: json['isVerified'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'avatarUrl': avatarUrl,
        'bio': bio,
        'location': location,
        'role': role.name,
        'createdAt': createdAt.toIso8601String(),
        'isVerified': isVerified,
      };

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    String? bio,
    String? location,
    UserRole? role,
    DateTime? createdAt,
    bool? isVerified,
  }) =>
      UserModel(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bio: bio ?? this.bio,
        location: location ?? this.location,
        role: role ?? this.role,
        createdAt: createdAt ?? this.createdAt,
        isVerified: isVerified ?? this.isVerified,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
