import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/buyer/domain/looking_for_feed_query.dart';
import 'package:thriftline/features/buyer/domain/looking_for_lifecycle.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/looking_for_model.dart';

void main() {
  LookingForModel post({
    required String id,
    ProductCategory category = ProductCategory.tops,
    double budgetMin = 100,
    double budgetMax = 500,
    String? size,
    String? image,
    int responses = 0,
    DateTime? createdAt,
    DateTime? expiresAt,
    LookingForStatus status = LookingForStatus.active,
    DateTime? observedAt,
  }) {
    return LookingForModel(
      id: id,
      buyerId: 'b1',
      buyerName: 'Buyer',
      buyerAvatar: '',
      title: 'Item $id',
      description: '',
      category: category,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      size: size,
      location: 'Davao',
      createdAt: createdAt ?? DateTime.utc(2026, 10, 1),
      responseCount: responses,
      thumbnailUrl: image,
      expiresAt: expiresAt,
      status: status,
      observedAt: observedAt,
    );
  }

  test('sorts by highest budget then recent', () {
    final a = post(id: 'a', budgetMax: 200);
    final b = post(id: 'b', budgetMax: 900);
    final out = queryLookingForPosts(
      [a, b],
      sort: LookingForSort.highestBudget,
    );
    expect(out.first.id, 'b');
  });

  test('filters by category and budget overlap', () {
    final match = post(
      id: 'm',
      category: ProductCategory.shoes,
      budgetMin: 400,
      budgetMax: 800,
    );
    final wrongCat = post(id: 'c', category: ProductCategory.tops);
    final out = queryLookingForPosts(
      [match, wrongCat],
      sort: LookingForSort.recentlyPosted,
      filters: LookingForFeedFilters(
        categories: {ProductCategory.shoes},
        minBudget: 500,
        maxBudget: 1500,
      ),
    );
    expect(out.map((p) => p.id), ['m']);
  });

  test('inactive status filter applies only when enabled', () {
    final now = DateTime.utc(2026, 10, 5, 12);
    final expired = post(
      id: 'e',
      expiresAt: now.subtract(const Duration(hours: 1)),
      observedAt: now,
    );
    final fulfilled = post(
      id: 'f',
      status: LookingForStatus.fulfilled,
      expiresAt: now.add(const Duration(days: 1)),
      observedAt: now,
    );
    final out = queryLookingForPosts(
      [expired, fulfilled],
      sort: LookingForSort.recentlyPosted,
      filters: const LookingForFeedFilters(
        inactiveStatus: LookingForInactiveStatusFilter.fulfilled,
      ),
      applyInactiveStatus: true,
    );
    expect(out.single.id, 'f');
  });
}
