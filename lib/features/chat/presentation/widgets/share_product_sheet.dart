import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product_model.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/chat_detail_controller.dart';

class ShareProductSheet extends StatefulWidget {
  const ShareProductSheet({super.key, required this.controller});

  final ChatDetailController controller;

  static Future<bool> show(
    BuildContext context, {
    required ChatDetailController controller,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareProductSheet(controller: controller),
    );
    return sent == true;
  }

  @override
  State<ShareProductSheet> createState() => _ShareProductSheetState();
}

class _ShareProductSheetState extends State<ShareProductSheet> {
  List<ProductModel> _products = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.controller.loadShareableProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
        if (products.isEmpty) {
          _error = 'No active listings in your shop to share.';
        }
      });
    } catch (e, st) {
      debugPrint('ShareProductSheet.load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your shop listings.';
      });
    }
  }

  Future<void> _share(ProductModel product) async {
    if (_sending) return;
    setState(() => _sending = true);
    final error = await widget.controller.sendProductShare(product.id);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.72,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Share product',
                      style: AppTypography.heading.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Pick an active listing from your shop to send in this chat.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final product = _products[i];
        final image =
            product.imageUrls.isNotEmpty ? product.imageUrls.first : null;
        return Material(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _sending ? null : () => _share(product),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: image != null && image.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColors.border,
                              child: const Icon(Icons.image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatCurrency(product.price),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_sending)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.send_outlined, color: AppColors.primary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
