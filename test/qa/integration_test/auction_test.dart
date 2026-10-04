import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/models/bid_model.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/product_model.dart';
import 'package:thriftline/widgets/countdown_timer.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

ProductModel _auctionProduct() => ProductModel(
  id: 'prod-auc-001',
  title: 'Rare Vintage Band Tee',
  description: 'Authentic 90s band tour tee',
  price: 500.0,
  imageUrls: const ['https://example.com/tee.jpg'],
  category: ProductCategory.tops,
  condition: ProductCondition.good,
  sellerId: 'seller-rock-1',
  sellerUsername: 'rock_vintage',
  sellerName: 'Rock Vintage Store',
  sellerAvatar: '',
  sellerVerified: true,
  sellingType: SellingType.auction,
  status: ProductStatus.active,
  quantityAvailable: 1,
  createdAt: DateTime.now(),
);

/// Supabase-style row for the product (used in UserBid.fromSupabase auction map)
Map<String, dynamic> _productRow(ProductModel p) => {
  'product_id': p.id,
  'name': p.title,
  'description': p.description,
  'price': p.price,
  'condition': 'good',
  'status': 'active',
  'quantity_available': p.quantityAvailable,
  'listing_type': 'auction',
  'created_at': p.createdAt.toIso8601String(),
};

/// Interactive Auction Screen simulating live bidding and timer expiration
class _AuctionBiddingHarness extends StatefulWidget {
  const _AuctionBiddingHarness({
    required this.product,
    required this.startingPrice,
    required this.minimumIncrement,
    required this.endTime,
    required this.onBidPlaced,
  });

  final ProductModel product;
  final double startingPrice;
  final double minimumIncrement;
  final DateTime endTime;
  final void Function(double amount) onBidPlaced;

  @override
  State<_AuctionBiddingHarness> createState() => _AuctionBiddingHarnessState();
}

class _AuctionBiddingHarnessState extends State<_AuctionBiddingHarness> {
  late double _currentPrice;
  final _bidController = TextEditingController();
  String? _bidError;
  bool _auctionEnded = false;

  @override
  void initState() {
    super.initState();
    _currentPrice = widget.startingPrice;
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  double get _minRequiredBid => _currentPrice + widget.minimumIncrement;

  void _submitBid() {
    setState(() => _bidError = null);

    if (_auctionEnded) {
      setState(() => _bidError = 'This auction has already ended.');
      return;
    }

    final entered = double.tryParse(_bidController.text.trim());
    if (entered == null) {
      setState(() => _bidError = 'Enter a valid amount.');
      return;
    }

    if (entered < _minRequiredBid) {
      setState(() {
        _bidError = 'Minimum bid is ${formatCurrency(_minRequiredBid)}';
      });
      return;
    }

    setState(() {
      _currentPrice = entered;
      _bidController.clear();
    });

    widget.onBidPlaced(entered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Time Remaining:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                CountdownTimer(
                  endTime: widget.endTime,
                  onExpired: () => setState(() => _auctionEnded = true),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Current Highest Bid:'),
                      Text(
                        formatCurrency(_currentPrice),
                        key: const Key('auction-current-price'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6C5CE7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Min Increment: +${formatCurrency(widget.minimumIncrement)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ThriftTextField(
              key: const Key('auction-bid-input'),
              label: 'Your Bid Amount (₱)',
              hint: 'Min. ${formatCurrency(_minRequiredBid)}',
              controller: _bidController,
              keyboardType: TextInputType.number,
              error: _bidError,
            ),
            const SizedBox(height: 16),
            ThriftButton(
              key: const Key('auction-place-bid-button'),
              label: 'Place Bid',
              onPressed: _submitBid,
            ),
          ],
        ),
      ),
    );
  }
}

Finder _bidInputField() => find.descendant(
  of: find.byKey(const Key('auction-bid-input')),
  matching: find.byType(TextFormField),
);

void auctionIntegrationTests() {
  qaGroup('Auction & Bidding Integration Flow', () {
    qaIntegrationTest('full bidding cycle with increments, validation & outbid handling', (
      tester,
    ) async {
      final product = _auctionProduct();
      final productRow = _productRow(product);

      final endTime = DateTime.now().add(const Duration(hours: 2));
      double? placedBidAmount;

      await tester.pumpWidget(
        MaterialApp(
          home: _AuctionBiddingHarness(
            product: product,
            startingPrice: 500.0,
            minimumIncrement: 50.0,
            endTime: endTime,
            onBidPlaced: (amt) => placedBidAmount = amt,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial price and countdown display
      expect(find.text(formatCurrency(500.0)), findsOneWidget);
      expect(find.text('Min Increment: +₱50'), findsOneWidget);

      // 1. Try placing an under-increment bid (520 instead of 550)
      await tester.enterText(_bidInputField(), '520');
      await tester.tap(find.byKey(const Key('auction-place-bid-button')));
      await tester.pumpAndSettle();

      expect(find.text('Minimum bid is ₱550'), findsOneWidget);
      expect(placedBidAmount, isNull);

      // 2. Place a valid winning bid of 600
      await tester.enterText(_bidInputField(), '600');
      await tester.tap(find.byKey(const Key('auction-place-bid-button')));
      await tester.pumpAndSettle();

      expect(placedBidAmount, 600.0);
      expect(find.text(formatCurrency(600.0)), findsOneWidget);
      expect(find.text('Minimum bid is ₱550'), findsNothing);

      // 3. UserBid state model transitions:
      // Current user is winning
      var userBid = UserBid.fromSupabase({
        'bid_id': 'bid-1',
        'bidder_id': 'buyer-qa-1',
        'bid_amount': 600.0,
        'is_highest_bid': true,
        'created_at': DateTime.now().toIso8601String(),
        'auction': {
          'auction_id': 'auc-1',
          'product_id': product.id,
          'starting_price': 500.0,
          'current_price': 600.0,
          'minimum_increment': 50.0,
          'winner_id': 'buyer-qa-1',
          'ends_at': endTime.toIso8601String(),
          'status': 'active',
          'product': productRow,
        },
      });

      expect(userBid.status, BidStatus.winning);
      expect(userBid.isHighestBid, isTrue);

      // Another user places 700 -> Current user gets outbid
      userBid = UserBid.fromSupabase({
        'bid_id': 'bid-1',
        'bidder_id': 'buyer-qa-1',
        'bid_amount': 600.0,
        'is_highest_bid': false,
        'created_at': DateTime.now().toIso8601String(),
        'auction': {
          'auction_id': 'auc-1',
          'product_id': product.id,
          'starting_price': 500.0,
          'current_price': 700.0,
          'minimum_increment': 50.0,
          'winner_id': 'another-buyer-2',
          'ends_at': endTime.toIso8601String(),
          'status': 'active',
          'product': productRow,
        },
      });

      expect(userBid.status, BidStatus.outbid);
      expect(userBid.isHighestBid, isFalse);

      // Auction ends and current user won
      userBid = UserBid.fromSupabase({
        'bid_id': 'bid-2',
        'bidder_id': 'buyer-qa-1',
        'bid_amount': 750.0,
        'is_highest_bid': true,
        'created_at': DateTime.now().toIso8601String(),
        'auction': {
          'auction_id': 'auc-1',
          'product_id': product.id,
          'starting_price': 500.0,
          'current_price': 750.0,
          'minimum_increment': 50.0,
          'winner_id': 'buyer-qa-1',
          'ends_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
          'status': 'ended',
          'product': productRow,
        },
      });

      expect(userBid.status, BidStatus.won);
    });

    qaIntegrationTest('auction countdown and formatters handle expiration gracefully', (
      tester,
    ) async {
      expect(formatCountdown(const Duration(hours: 1, minutes: 30)), '01:30');
      expect(formatCountdown(Duration.zero), 'Ended');
      expect(formatCountdown(const Duration(seconds: -10)), 'Ended');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    auctionIntegrationTests();
  });
}
