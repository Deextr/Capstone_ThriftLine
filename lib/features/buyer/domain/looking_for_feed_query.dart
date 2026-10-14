import '../../../models/enums.dart';
import '../../../models/looking_for_model.dart';
import 'looking_for_lifecycle.dart';

enum LookingForSort {
  recentlyPosted,
  mostPopular,
  highestBudget,
  lowestBudget,
  expiringSoon,
}

enum LookingForInactiveStatusFilter { all, expired, fulfilled }

/// Client-side filters applied to loaded Looking For rows (no extra API calls).
class LookingForFeedFilters {
  const LookingForFeedFilters({
    this.categories = const {},
    this.minBudget,
    this.maxBudget,
    this.referenceImageOnly = false,
    this.withSizeOnly = false,
    this.inactiveStatus = LookingForInactiveStatusFilter.all,
  });

  final Set<ProductCategory> categories;
  final double? minBudget;
  final double? maxBudget;
  final bool referenceImageOnly;
  final bool withSizeOnly;
  final LookingForInactiveStatusFilter inactiveStatus;

  bool get hasCategoryFilter => categories.isNotEmpty;
  bool get hasBudgetFilter => minBudget != null || maxBudget != null;
  bool get hasReferenceImageFilter => referenceImageOnly;
  bool get hasSizeFilter => withSizeOnly;
  bool get hasInactiveStatusFilter =>
      inactiveStatus != LookingForInactiveStatusFilter.all;

  int get activeFilterCount {
    var n = 0;
    if (hasCategoryFilter) n++;
    if (hasBudgetFilter) n++;
    if (hasReferenceImageFilter) n++;
    if (hasSizeFilter) n++;
    if (hasInactiveStatusFilter) n++;
    return n;
  }

  bool get hasAnyFilter => activeFilterCount > 0;

  LookingForFeedFilters clearAll() => const LookingForFeedFilters();

  LookingForFeedFilters copyWith({
    Set<ProductCategory>? categories,
    double? minBudget,
    double? maxBudget,
    bool? referenceImageOnly,
    bool? withSizeOnly,
    LookingForInactiveStatusFilter? inactiveStatus,
    bool clearMinBudget = false,
    bool clearMaxBudget = false,
    bool clearCategories = false,
  }) {
    return LookingForFeedFilters(
      categories: clearCategories ? const {} : (categories ?? this.categories),
      minBudget: clearMinBudget ? null : (minBudget ?? this.minBudget),
      maxBudget: clearMaxBudget ? null : (maxBudget ?? this.maxBudget),
      referenceImageOnly: referenceImageOnly ?? this.referenceImageOnly,
      withSizeOnly: withSizeOnly ?? this.withSizeOnly,
      inactiveStatus: inactiveStatus ?? this.inactiveStatus,
    );
  }
}

String lookingForSortLabel(LookingForSort sort) => switch (sort) {
  LookingForSort.recentlyPosted => 'Recently posted',
  LookingForSort.mostPopular => 'Most popular',
  LookingForSort.highestBudget => 'Highest budget',
  LookingForSort.lowestBudget => 'Lowest budget',
  LookingForSort.expiringSoon => 'Expiring soon',
};

String lookingForSortShortLabel(LookingForSort sort) => switch (sort) {
  LookingForSort.recentlyPosted => 'Recent',
  LookingForSort.mostPopular => 'Popular',
  LookingForSort.highestBudget => 'Top budget',
  LookingForSort.lowestBudget => 'Low budget',
  LookingForSort.expiringSoon => 'Expiring',
};

bool lookingForBudgetRangeOverlaps({
  required double postMin,
  required double postMax,
  double? filterMin,
  double? filterMax,
}) {
  final lo = filterMin ?? 0;
  final hi = filterMax ?? double.infinity;
  return postMax >= lo && postMin <= hi;
}

bool lookingForPostMatchesFilters(
  LookingForModel post,
  LookingForFeedFilters filters, {
  required bool applyInactiveStatus,
}) {
  if (filters.hasCategoryFilter && !filters.categories.contains(post.category)) {
    return false;
  }
  if (filters.hasBudgetFilter &&
      !lookingForBudgetRangeOverlaps(
        postMin: post.budgetMin,
        postMax: post.budgetMax,
        filterMin: filters.minBudget,
        filterMax: filters.maxBudget,
      )) {
    return false;
  }
  if (filters.referenceImageOnly) {
    final url = post.thumbnailUrl?.trim() ?? '';
    if (url.isEmpty) return false;
  }
  if (filters.withSizeOnly) {
    final size = post.size?.trim() ?? '';
    if (size.isEmpty) return false;
  }
  if (applyInactiveStatus && filters.hasInactiveStatusFilter) {
    final lifecycle = post.lifecycle;
    return switch (filters.inactiveStatus) {
      LookingForInactiveStatusFilter.expired =>
        lifecycle == LookingForLifecycle.expired,
      LookingForInactiveStatusFilter.fulfilled =>
        lifecycle == LookingForLifecycle.fulfilled ||
            lifecycle == LookingForLifecycle.closed,
      LookingForInactiveStatusFilter.all => true,
    };
  }
  return true;
}

void sortLookingForPosts(List<LookingForModel> posts, LookingForSort sort) {
  posts.sort((a, b) {
    return switch (sort) {
      LookingForSort.mostPopular =>
        b.responseCount.compareTo(a.responseCount) != 0
            ? b.responseCount.compareTo(a.responseCount)
            : b.createdAt.compareTo(a.createdAt),
      LookingForSort.highestBudget =>
        b.budgetMax.compareTo(a.budgetMax) != 0
            ? b.budgetMax.compareTo(a.budgetMax)
            : b.createdAt.compareTo(a.createdAt),
      LookingForSort.lowestBudget =>
        a.budgetMin.compareTo(b.budgetMin) != 0
            ? a.budgetMin.compareTo(b.budgetMin)
            : b.createdAt.compareTo(a.createdAt),
      LookingForSort.expiringSoon => () {
        final ae = a.expiresAt;
        final be = b.expiresAt;
        if (ae == null && be == null) return b.createdAt.compareTo(a.createdAt);
        if (ae == null) return 1;
        if (be == null) return -1;
        final byExpiry = ae.compareTo(be);
        return byExpiry != 0 ? byExpiry : b.createdAt.compareTo(a.createdAt);
      }(),
      LookingForSort.recentlyPosted => b.createdAt.compareTo(a.createdAt),
    };
  });
}

List<LookingForModel> queryLookingForPosts(
  Iterable<LookingForModel> source, {
  required LookingForSort sort,
  LookingForFeedFilters filters = const LookingForFeedFilters(),
  bool applyInactiveStatus = false,
}) {
  final filtered = source
      .where(
        (p) => lookingForPostMatchesFilters(
          p,
          filters,
          applyInactiveStatus: applyInactiveStatus,
        ),
      )
      .toList();
  sortLookingForPosts(filtered, sort);
  return filtered;
}
