import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/supabase_rpc.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/listing_bucket.dart';
import '../widgets/end_auction_dialog.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Local model
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ListingItem {
  const _ListingItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.status,
    required this.listingType,
    required this.condition,
    required this.bucket,
    this.primaryImageUrl,
    this.brand,
    this.size,
    this.auctionId,
    this.auctionStatus,
    this.endsAt,
    this.winnerId,
    this.bidCount = 0,
    this.paymentDueAt,
    this.orderStatus,
  });

  final String productId;
  final String name;
  final double price;
  final String status;
  final String listingType;
  final String condition;
  final ListingBucket bucket;
  final String? primaryImageUrl;
  final String? brand;
  final String? size;
  final String? auctionId;
  final String? auctionStatus;
  final DateTime? endsAt;
  final String? winnerId;
  final int bidCount;
  final DateTime? paymentDueAt;
  final String? orderStatus;

  ListingSnapshot snapshotAt(DateTime now) => ListingSnapshot(
    productStatus: status,
    listingType: listingType,
    auctionStatus: auctionStatus,
    endsAt: endsAt,
    winnerId: winnerId,
    orderStatus: orderStatus,
    paymentDueAt: paymentDueAt,
    bidCount: bidCount,
    now: now,
  );

  factory _ListingItem.fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? order,
    required DateTime now,
  }) {
    final images = row['product_images'] as List? ?? [];
    final primary = images.isNotEmpty
        ? images.firstWhere(
            (i) => i['is_primary'] == true,
            orElse: () => images.first,
          )
        : null;
    final auction = _auctionMap(row['auctions']);
    final endsAt = auction?['ends_at'] != null
        ? DateTime.tryParse(auction!['ends_at'] as String)
        : null;
    final due = order?['payment_due_at'] != null
        ? DateTime.tryParse(order!['payment_due_at'] as String)
        : null;
    final status = row['status'] as String? ?? 'active';
    final listingType = row['listing_type'] as String? ?? 'fixed_price';
    final auctionStatus = auction?['status'] as String?;
    final winnerId = auction?['winner_id'] as String?;
    final orderStatus = order?['order_status'] as String?;
    final bidCount = (auction?['bid_count'] as num?)?.toInt() ?? 0;
    final current = (auction?['current_price'] as num?)?.toDouble();
    final snapshot = ListingSnapshot(
      productStatus: status,
      listingType: listingType,
      auctionStatus: auctionStatus,
      endsAt: endsAt,
      winnerId: winnerId,
      orderStatus: orderStatus,
      paymentDueAt: due,
      bidCount: bidCount,
      now: now,
    );

    return _ListingItem(
      productId: row['product_id'] as String,
      name: row['name'] as String? ?? row['title'] as String? ?? '',
      price: current ?? (row['price'] as num?)?.toDouble() ?? 0,
      status: status,
      listingType: listingType,
      condition: row['condition'] as String? ?? '',
      bucket: listingBucketFor(snapshot),
      primaryImageUrl: primary?['image_url'] as String?,
      brand: row['brand'] as String?,
      size: row['size'] as String?,
      auctionId: auction?['auction_id'] as String?,
      auctionStatus: auctionStatus,
      endsAt: endsAt,
      winnerId: winnerId,
      bidCount: bidCount,
      paymentDueAt: due,
      orderStatus: orderStatus,
    );
  }
}

Map<String, dynamic>? _auctionMap(dynamic raw) {
  if (raw is List && raw.isNotEmpty && raw.first is Map) {
    return Map<String, dynamic>.from(raw.first as Map);
  }
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({super.key});

  @override
  State<SellerListingsTab> createState() => _SellerListingsTabState();
}

class _SellerListingsTabState extends State<SellerListingsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  List<_ListingItem> _active = [];
  List<_ListingItem> _awaiting = [];
  List<_ListingItem> _sold = [];
  List<_ListingItem> _inactive = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final supabase = context.read<SupabaseService>();
      final sellerId = auth.user?.id;

      if (sellerId == null) {
        setState(() {
          _loading = false;
          _error = 'Not logged in.';
        });
        return;
      }

      try {
        await supabase.client.rpc('close_auctions');
      } catch (error) {
        debugPrint('SellerListingsTab.close_auctions: $error');
      }

      final rows = await supabase.client
          .from('products')
          .select(
            'product_id, name, price, status, listing_type, condition, brand, size, '
            'product_images(image_url, is_primary), '
            'auctions(auction_id, status, ends_at, winner_id, current_price, bid_count)',
          )
          .eq('seller_id', sellerId)
          .inFilter('status', ['active', 'sold'])
          .order('created_at', ascending: false);

      final productRows = (rows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      final auctionIds = productRows
          .map((row) => _auctionMap(row['auctions'])?['auction_id'] as String?)
          .whereType<String>()
          .toList();
      final ordersByAuction = <String, Map<String, dynamic>>{};
      if (auctionIds.isNotEmpty) {
        final orderRows = await supabase.client
            .from('orders')
            .select('auction_id, order_status, payment_due_at')
            .inFilter('auction_id', auctionIds);
        for (final raw in orderRows as List) {
          final order = Map<String, dynamic>.from(raw as Map);
          final auctionId = order['auction_id'] as String?;
          if (auctionId != null) ordersByAuction[auctionId] = order;
        }
      }

      final now = DateTime.now();
      final items = productRows
          .map(
            (row) => _ListingItem.fromRow(
              row,
              order:
                  ordersByAuction[_auctionMap(row['auctions'])?['auction_id']],
              now: now,
            ),
          )
          .toList();

      if (mounted) {
        setState(() {
          _active = items
              .where((i) => i.bucket == ListingBucket.active)
              .toList();
          _awaiting = items
              .where((i) => i.bucket == ListingBucket.awaitingPayment)
              .toList();
          _sold = items.where((i) => i.bucket == ListingBucket.sold).toList();
          _inactive = items
              .where((i) => i.bucket == ListingBucket.inactive)
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load listings: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingMd,
                AppConstants.spacingMd,
                AppConstants.spacingMd,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('My Listings', style: AppTypography.heading),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            TabBar(
              controller: _tab,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: [
                Tab(text: 'Active (${_active.length})'),
                Tab(text: 'Awaiting payment (${_awaiting.length})'),
                Tab(text: 'Sold (${_sold.length})'),
                Tab(text: 'Inactive (${_inactive.length})'),
              ],
            ),
            Expanded(
              child: _error != null
                  ? _ErrorView(message: _error!, onRetry: _load)
                  : TabBarView(
                      controller: _tab,
                      children: [
                        _ListingsList(
                          items: _active,
                          loading: _loading,
                          emptyMessage:
                              'No active listings yet.\nTap + to add one.',
                          onRefresh: _load,
                          onChanged: _load,
                        ),
                        _ListingsList(
                          items: _awaiting,
                          loading: _loading,
                          emptyMessage: 'No auctions waiting for payment.',
                          onRefresh: _load,
                          onChanged: _load,
                        ),
                        _ListingsList(
                          items: _sold,
                          loading: _loading,
                          emptyMessage: 'No sold listings.',
                          onRefresh: _load,
                          onChanged: _load,
                        ),
                        _ListingsList(
                          items: _inactive,
                          loading: _loading,
                          emptyMessage: 'No inactive auctions.',
                          onRefresh: _load,
                          onChanged: _load,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 72.0),
        child: FloatingActionButton(
          onPressed: () =>
              context.push(RouteNames.addListing).then((_) => _load()),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Listings list
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ListingsList extends StatelessWidget {
  const _ListingsList({
    required this.items,
    required this.loading,
    required this.emptyMessage,
    required this.onRefresh,
    required this.onChanged,
  });

  final List<_ListingItem> items;
  final bool loading;
  final String emptyMessage;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  emptyMessage,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: items.length,
        itemBuilder: (_, i) =>
            _ListingCard(item: items[i], onChanged: onChanged),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Individual listing card
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.item, required this.onChanged});

  final _ListingItem item;
  final Future<void> Function() onChanged;

  bool get _hasMenu {
    final snapshot = item.snapshotAt(DateTime.now());
    return item.bucket == ListingBucket.active ||
        item.bucket == ListingBucket.inactive ||
        canEndAuctionEarly(snapshot) ||
        canRelistAuction(snapshot);
  }

  String _formatLabel(String listingType) {
    if (listingType == 'fixed_price') return 'Fixed';
    if (listingType == 'auction') return 'Auction';
    return listingType;
  }

  String _conditionLabel(String condition) {
    if (condition == 'new') return 'New with tags';
    if (condition == 'like_new') return 'Like new';
    if (condition == 'good') return 'Good';
    if (condition == 'fair') return 'Fair';
    return condition;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
      child: ThriftCard(
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: SizedBox(
                width: 72,
                height: 72,
                child: item.primaryImageUrl != null
                    ? Image.network(
                        item.primaryImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: AppConstants.spacingMd),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppTypography.subheading.copyWith(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u20B1${item.price.toStringAsFixed(2)}',
                    style: AppTypography.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Chip(
                        label: _formatLabel(item.listingType),
                        color: AppColors.primary,
                      ),
                      if (item.bucket == ListingBucket.awaitingPayment)
                        const _Chip(
                          label: 'Awaiting payment',
                          color: AppColors.primary,
                        ),
                      _Chip(
                        label: _conditionLabel(item.condition),
                        color: AppColors.textSecondary,
                      ),
                      if (item.size != null)
                        _Chip(
                          label: item.size!,
                          color: AppColors.textSecondary,
                        ),
                    ],
                  ),
                  if (item.bucket == ListingBucket.awaitingPayment &&
                      item.paymentDueAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatPaymentDeadline(item.paymentDueAt!),
                      style: AppTypography.caption,
                    ),
                  ],
                ],
              ),
            ),

            if (_hasMenu)
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  color: AppColors.textSecondary,
                ),
                onSelected: (value) => _onMenuAction(context, value),
                itemBuilder: (_) {
                  final snapshot = item.snapshotAt(DateTime.now());
                  return [
                    if (item.bucket == ListingBucket.active)
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (canEndAuctionEarly(snapshot))
                      const PopupMenuItem(
                        value: 'end',
                        child: Text('End auction early'),
                      ),
                    if (canRelistAuction(snapshot))
                      const PopupMenuItem(
                        value: 'relist',
                        child: Text('Relist'),
                      ),
                    if (item.bucket == ListingBucket.active ||
                        item.bucket == ListingBucket.inactive)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                  ];
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.primaryLight,
      child: const Center(
        child: Icon(Icons.image_outlined, color: AppColors.textHint, size: 28),
      ),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
    if (action == 'edit') {
      final path = RouteNames.editListing.replaceFirst(':id', item.productId);
      await context.push(path);
      await onChanged();
      return;
    }

    if (action == 'end') {
      final accepted = await confirmEndAuctionEarly(
        context,
        highestBid: item.price,
      );
      if (!accepted || !context.mounted) return;
      final auctionId = item.auctionId;
      if (auctionId == null) return;
      try {
        final result = await context.read<SupabaseService>().client.rpc(
          'end_auction_early',
          params: {'p_auction_id': auctionId},
        );
        if (!context.mounted) return;
        if (!supabaseRpcSuccess(result)) {
          showThriftSnackBar(
            context,
            supabaseRpcError(result, fallback: 'Could not end this auction.') ??
                'Could not end this auction.',
            isError: true,
          );
          return;
        }
        showThriftSnackBar(
          context,
          'Auction ended. The winner has 12 hours to pay.',
        );
        await onChanged();
      } catch (e) {
        if (context.mounted) {
          showThriftSnackBar(
            context,
            'Could not end this auction.',
            isError: true,
          );
        }
      }
      return;
    }

    if (action == 'relist') {
      final days = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Relist auction'),
          children: [
            for (final option in const [1, 3, 5, 7])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, option),
                child: Text('$option day${option == 1 ? '' : 's'}'),
              ),
          ],
        ),
      );
      if (days == null || !context.mounted) return;
      try {
        final result = await context.read<SupabaseService>().client.rpc(
          'relist_unsold_auction',
          params: {'p_product_id': item.productId, 'p_duration_days': days},
        );
        if (!context.mounted) return;
        if (!supabaseRpcSuccess(result)) {
          showThriftSnackBar(
            context,
            supabaseRpcError(
                  result,
                  fallback: 'Could not relist this auction.',
                ) ??
                'Could not relist this auction.',
            isError: true,
          );
          return;
        }
        showThriftSnackBar(context, 'Auction relisted.');
        await onChanged();
      } catch (e) {
        if (context.mounted) {
          showThriftSnackBar(
            context,
            'Could not relist this auction.',
            isError: true,
          );
        }
      }
      return;
    }

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete listing?'),
          content: Text(
            'Are you sure you want to delete "${item.name}"? This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed == true && context.mounted) {
        try {
          final supabase = context.read<SupabaseService>();
          await supabase.client
              .from('products')
              .update({'status': 'removed'})
              .eq('product_id', item.productId);
          if (context.mounted) {
            showThriftSnackBar(context, 'Listing deleted');
            await onChanged();
          }
        } catch (e) {
          if (context.mounted) {
            showThriftSnackBar(context, 'Failed to delete: $e', isError: true);
          }
        }
      }
    }
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Chip badge
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: color, fontSize: 10),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Error view
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingMd),
            ThriftButton(label: 'Retry', onPressed: onRetry, expand: false),
          ],
        ),
      ),
    );
  }
}
