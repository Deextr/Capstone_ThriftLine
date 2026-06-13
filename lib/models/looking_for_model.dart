import 'enums.dart';

class LookingForModel {
  const LookingForModel({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.buyerAvatar,
    required this.title,
    required this.description,
    required this.category,
    required this.budgetMin,
    required this.budgetMax,
    this.size,
    required this.location,
    required this.createdAt,
    this.responseCount = 0,
    this.status = LookingForStatus.active,
  });

  final String id;
  final String buyerId;
  final String buyerName;
  final String buyerAvatar;
  final String title;
  final String description;
  final ProductCategory category;
  final double budgetMin;
  final double budgetMax;
  final String? size;
  final String location;
  final DateTime createdAt;
  final int responseCount;
  final LookingForStatus status;
}
