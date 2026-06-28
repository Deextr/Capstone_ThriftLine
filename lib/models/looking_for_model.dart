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
    this.thumbnailUrl,
    this.likesCount = 0,
    this.sharesCount = 0,
    this.isLiked = false,
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
  final String? thumbnailUrl;
  final int likesCount;
  final int sharesCount;
  final bool isLiked;

  LookingForModel copyWith({
    String? id,
    String? buyerId,
    String? buyerName,
    String? buyerAvatar,
    String? title,
    String? description,
    ProductCategory? category,
    double? budgetMin,
    double? budgetMax,
    String? size,
    String? location,
    DateTime? createdAt,
    int? responseCount,
    LookingForStatus? status,
    String? thumbnailUrl,
    int? likesCount,
    int? sharesCount,
    bool? isLiked,
  }) {
    return LookingForModel(
      id: id ?? this.id,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      buyerAvatar: buyerAvatar ?? this.buyerAvatar,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      budgetMin: budgetMin ?? this.budgetMin,
      budgetMax: budgetMax ?? this.budgetMax,
      size: size ?? this.size,
      location: location ?? this.location,
      createdAt: createdAt ?? this.createdAt,
      responseCount: responseCount ?? this.responseCount,
      status: status ?? this.status,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      likesCount: likesCount ?? this.likesCount,
      sharesCount: sharesCount ?? this.sharesCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}
