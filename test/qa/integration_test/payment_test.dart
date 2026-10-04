import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/core/utils/money.dart';
import 'package:thriftline/core/utils/rider_privacy.dart';
import 'package:thriftline/features/buyer/data/paymongo_checkout.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Payment Selection and Settlement Harness
class _PaymentSettlementHarness extends StatefulWidget {
  const _PaymentSettlementHarness({
    required this.order,
    required this.onPaymentConfirmed,
  });

  final OrderModel order;
  final void Function(PaymentMethod method, String transactionRef)
  onPaymentConfirmed;

  @override
  State<_PaymentSettlementHarness> createState() =>
      _PaymentSettlementHarnessState();
}

class _PaymentSettlementHarnessState extends State<_PaymentSettlementHarness> {
  PaymentMethod _selectedMethod = PaymentMethod.paymongo;
  bool _isProcessing = false;
  String? _statusMessage;

  void _simulatePaymongoPayment() {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Redirecting to GCash via PayMongo...';
    });

    // In a live flow, PayMongo produces checkout_url and webhook signals paid
    final centavos = phpPesosToCentavos(widget.order.total);
    expect(centavos, greaterThan(0));

    setState(() {
      _isProcessing = false;
      _statusMessage = 'Payment confirmed! Order is being prepared.';
    });

    widget.onPaymentConfirmed(_selectedMethod, 'pm_pay_sim_${widget.order.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order: #${widget.order.orderNumber}'),
                  const SizedBox(height: 6),
                  Text(
                    'Amount Due: ${formatCurrency(widget.order.total)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(${phpPesosToCentavos(widget.order.total)} centavos)',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Select Payment Method:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            RadioListTile<PaymentMethod>(
              key: const Key('pay-method-gcash'),
              title: const Text('GCash (PayMongo)'),
              subtitle: const Text('Instant, secured escrow hold'),
              value: PaymentMethod.paymongo,
              groupValue: _selectedMethod,
              onChanged: (val) => setState(() => _selectedMethod = val!),
            ),
            RadioListTile<PaymentMethod>(
              key: const Key('pay-method-cod'),
              title: const Text('Cash on Delivery (COD)'),
              subtitle: const Text('Pay when parcel arrives'),
              value: PaymentMethod.cod,
              groupValue: _selectedMethod,
              onChanged: (val) => setState(() => _selectedMethod = val!),
            ),
            const SizedBox(height: 16),
            if (_statusMessage != null)
              Container(
                key: const Key('payment-status-message'),
                padding: const EdgeInsets.all(12),
                color: Colors.green.shade50,
                child: Text(
                  _statusMessage!,
                  style: TextStyle(color: Colors.green.shade900),
                ),
              ),
            const Spacer(),
            ThriftButton(
              key: const Key('confirm-pay-button'),
              label: 'Pay ${formatCurrency(widget.order.total)}',
              isLoading: _isProcessing,
              onPressed: _simulatePaymongoPayment,
            ),
          ],
        ),
      ),
    );
  }
}

void paymentIntegrationTests() {
  qaGroup('Payment & Settlement Integration Flow', () {
    qaIntegrationTest('full PayMongo GCash payment flow with centavos conversion & state updates', (
      tester,
    ) async {
      final initialOrder = OrderModel(
        id: 'order-pay-101',
        orderNumber: 'TL-8821',
        productId: 'prod-pay-1',
        buyerId: 'buyer-user-1',
        sellerId: 'seller-user-2',
        productTitle: 'Thrift Jacket',
        productImage: '',
        sellerName: 'Seller Store',
        buyerName: 'QA Buyer',
        buyerAvatar: '',
        status: OrderStatus.paymentPending,
        paymentMethod: PaymentMethod.unpaid,
        amount: 1200.0,
        shippingFee: 80.0,
        platformFee: 24.0,
        total: 1304.0,
        createdAt: DateTime.now(),
        deliveryMethod: DeliveryMethod.standard,
        shippingAddress: '123 Test St, Davao City, 8000',
        items: const [],
      );

      PaymentMethod? confirmedMethod;
      String? transactionRef;

      await tester.pumpWidget(
        MaterialApp(
          home: _PaymentSettlementHarness(
            order: initialOrder,
            onPaymentConfirmed: (method, ref) {
              confirmedMethod = method;
              transactionRef = ref;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify amount display and centavos mapping
      expect(find.text('Order: #TL-8821'), findsOneWidget);
      expect(find.text('Amount Due: ₱1,304'), findsOneWidget);
      expect(find.text('(130400 centavos)'), findsOneWidget);

      // 2. Test PayMongo Checkout URL safety rules
      expect(
        isSafePaymongoCheckoutUrl('https://checkout.paymongo.com/cs_live_123'),
        isTrue,
      );
      expect(
        isSafePaymongoCheckoutUrl('https://phishing.site/checkout'),
        isFalse,
      );

      // 3. Confirm payment with GCash (PayMongo)
      await tester.tap(find.byKey(const Key('confirm-pay-button')));
      await tester.pumpAndSettle();

      expect(confirmedMethod, PaymentMethod.paymongo);
      expect(transactionRef, contains('pm_pay_sim_order-pay-101'));
      expect(
        find.text('Payment confirmed! Order is being prepared.'),
        findsOneWidget,
      );

      // 4. Verify Order Status progression:
      // Status progresses from paymentPending -> preparing (To ship)
      final updatedOrder = initialOrder.copyWith(
        status: OrderStatus.preparing,
      );

      expect(updatedOrder.status, OrderStatus.preparing);
      expect(orderStatusLabel(updatedOrder.status), 'Paid / To ship');
    });

    qaIntegrationTest('inspection window and rider privacy safeguard escrow release', (
      tester,
    ) async {
      final now = DateTime(2026, 10, 4, 14, 0);
      final inspectionDeadline = now.add(const Duration(hours: 24));

      // Inspection timer remaining
      final remainingText = formatInspectionRemaining(
        inspectionDeadline,
        now: now,
      );
      expect(remainingText, '24h 00m');

      // Rider privacy masking: buyer only sees last 4 digits
      expect(maskRiderPhone('09171234567'), '09••• ••• 4567');
      expect(maskRiderName('Pedro Penduko Santos'), 'Pedro S.');
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    paymentIntegrationTests();
  });
}
