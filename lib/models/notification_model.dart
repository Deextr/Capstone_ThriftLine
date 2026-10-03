import 'enums.dart';

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.audience,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.data = const {},
  });

  final String id;
  final String userId;
  final NotificationType type;
  final NotificationAudience audience;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, String> data;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['notification_id'] as String? ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      type: NotificationType.fromString(json['type'] as String? ?? 'system'),
      audience: NotificationAudience.fromString(json['audience'] as String?),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      data: notificationPayload(json['data']),
    );
  }

  NotificationModel copyWith({bool? isRead, Map<String, String>? data}) =>
      NotificationModel(
        id: id,
        userId: userId,
        type: type,
        audience: audience,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        data: data ?? this.data,
      );
}

Map<String, String> notificationPayload(dynamic raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key.toString(): '${entry.value ?? ''}',
  };
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Reported-user notices set `can_appeal`. Reporter notices must not open this.
String? notificationAppealReportId(Map<String, String> data) {
  if (data['can_appeal'] != 'true') return null;
  final id = data['report_id']?.trim() ?? '';
  if (!_uuidPattern.hasMatch(id)) return null;
  return id;
}
