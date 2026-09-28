import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/presentation/widgets/seller_available_earnings_card.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required String amount,
  required String status,
  bool showPayout = false,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SellerAvailableEarningsCard(
          amountLabel: amount,
          statusLine: status,
          listingsLabel: '12',
          pendingLabel: '2',
          ratingLabel: '4.5',
          showPayout: showPayout,
          onRequestPayout: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('large available earnings stay on one line', (tester) async {
    await _pumpCard(
      tester,
      amount: '₱1,250,000.00',
      status: 'Ready for payout',
      showPayout: true,
    );

    expect(find.text('Available earnings'), findsOneWidget);
    expect(find.text('₱1,250,000.00'), findsOneWidget);
    expect(find.text('Request payout'), findsOneWidget);
    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text does not overflow the earnings card', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SellerAvailableEarningsCard(
              amountLabel: '₱1,250,000.00',
              statusLine: 'Ready for payout',
              listingsLabel: '128',
              pendingLabel: '12',
              ratingLabel: '4.8',
              showPayout: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('₱1,250,000.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings card lays out inside a scrolling dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              SellerAvailableEarningsCard(
                amountLabel: '₱45,200',
                statusLine: 'Ready for payout',
                listingsLabel: '6',
                pendingLabel: '0',
                ratingLabel: '4.5',
                showPayout: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('₱45,200'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero earnings does not offer a payout', (tester) async {
    await _pumpCard(
      tester,
      amount: '₱0.00',
      status: 'No earnings available yet',
    );

    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.text('Request payout'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading does not show a zero balance', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SellerAvailableEarningsCard(isLoading: true)),
      ),
    );

    expect(find.text('Available earnings'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.text('Listings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error keeps the card and does not show a balance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SellerAvailableEarningsCard(
            errorMessage: 'Unable to load earnings.',
          ),
        ),
      ),
    );

    expect(find.text('Unable to load balance'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(find.textContaining('SQL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping request payout, listings, pending, and retry triggers callbacks', (tester) async {
    var payoutTapped = false;
    var listingsTapped = false;
    var pendingTapped = false;
    var retryTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerAvailableEarningsCard(
            amountLabel: '₱45,200.00',
            statusLine: 'Ready for payout',
            listingsLabel: '8',
            pendingLabel: '3',
            ratingLabel: '4.9',
            showPayout: true,
            onRequestPayout: () => payoutTapped = true,
            onListings: () => listingsTapped = true,
            onPending: () => pendingTapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Request payout'));
    expect(payoutTapped, isTrue);

    await tester.tap(find.text('Listings'));
    expect(listingsTapped, isTrue);

    await tester.tap(find.text('Pending'));
    expect(pendingTapped, isTrue);

    // Test retry callback in error state
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerAvailableEarningsCard(
            errorMessage: 'Network error',
            onRetry: () => retryTapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    expect(retryTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders properly across small, standard, and large phone widths', (tester) async {
    final sizes = [
      const Size(320, 640), // small phone
      const Size(390, 844), // standard phone
      const Size(430, 932), // large phone
    ];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      for (final amount in ['₱0.00', '₱500.00', '₱45,200.00', '₱1,250,000.00']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SellerAvailableEarningsCard(
                amountLabel: amount,
                statusLine: amount == '₱0.00' ? 'No earnings available yet' : 'Ready for payout',
                listingsLabel: '14',
                pendingLabel: '2',
                ratingLabel: '4.8',
                showPayout: amount != '₱0.00',
              ),
            ),
          ),
        );

        expect(find.text(amount), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
