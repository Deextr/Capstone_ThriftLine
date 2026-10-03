/// When the Favorite / saved-items action may be shown or performed.
bool canShowProductFavoriteAction({
  required bool isBuyerExperience,
  required String? viewerUserId,
  required String? productSellerId,
}) {
  if (!isBuyerExperience) return false;
  if (viewerUserId == null || viewerUserId.isEmpty) return false;
  if (productSellerId == null || productSellerId.isEmpty) return false;
  return viewerUserId != productSellerId;
}

/// Server-aligned rule: users must not save their own listings.
bool canPersistProductSave({
  required String viewerUserId,
  required String? productSellerId,
}) {
  if (productSellerId == null || productSellerId.isEmpty) return false;
  return viewerUserId != productSellerId;
}
