import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/core/utils/rider_privacy.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/models/order_model.dart';
import 'package:thriftline/models/shipment_model.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

import '../support/qa_reporter.dart';

/// Order tracking harness displaying the shipment lifecycle.
class _OrderTrackingHarness extends StatefulWidget {
  const _OrderTrackingHarness({
    required this.order,
    required this.onConfirmReceived,
  });

  final OrderModel order;
  final void Function() onConfirmReceived;

  @override
  State<_OrderTrackingHarness> createState() => _OrderTrackingHarnessState();
}

class _OrderTrackingHarnessState extends State<_OrderTrackingHarness> {
  late OrderModel _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _order.shipment;
    return Scaffold(
      appBar: AppBar(title: Text('Track Order #${_order.orderNumber}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThriftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _order.productTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${_order.trackingStatusLabel}',
                    key: const Key('tracking-status-label'),
                  ),
                  const SizedBox(height: 4),
                  Text('Total: ${formatCurrency(_order.total)}'),
                ],
              ),
            ),
            if (shipment != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Delivery Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (shipment.shouldShowBuyerRiderInfo) ...[
                ThriftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rider: ${shipment.buyerRiderDisplayName()}',
                        key: const Key('tracking-rider-name'),
                      ),
                      if (shipment.isRiderContactVisibleToBuyer)
                        Text(
                          'Contact: ${shipment.buyerRiderPhone()}',
                          key: const Key('tracking-rider-phone'),
                        ),
                      Text('Vehicle: ${shipment.vehicleLabel}'),
                    ],
                  ),
                ),
              ],
              if (shipment.isFailed && shipment.deliveryFailureSummary != null)
                Container(
                  key: const Key('tracking-failure-banner'),
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(top: 16),
                  color: Colors.red.shade100,
                  child: Text(
                    'Delivery Failed: ${shipment.deliveryFailureSummary}',
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              if (shipment.isInspecting)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ThriftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Inspection Period',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Check your item and confirm receipt within 24h.',
                        ),
                        const SizedBox(height: 12),
                        ThriftButton(
                          key: const Key('tracking-confirm-received'),
                          label: 'Confirm Item Received',
                          onPressed: () {
                            widget.onConfirmReceived();
                            setState(() {
                              _order = _order.copyWith(
                                status: OrderStatus.completed,
                                shipment: ShipmentModel(
                                  id: shipment.id,
                                  orderId: shipment.orderId,
                                  deliveryStatus: DeliveryStatus.completed,
                                  buyerConfirmedReceived: true,
                                  buyerConfirmedReceivedAt: DateTime.now(),
                                  completedAt: DateTime.now(),
                                ),
                              );
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (_order.isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  key: const Key('tracking-completed-banner'),
                  padding: const EdgeInsets.all(12),
                  color: Colors.green.shade100,
                  child: Text(
                    'Order Completed! Thank you for shopping.',
                    style: TextStyle(color: Colors.green.shade900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

void orderTrackingIntegrationTests() {
  qaGroup('Order Tracking & Delivery Integration Flow', () {
    qaIntegrationTest(
        'full delivery lifecycle from preparing to buyer-confirmed completion', (
      tester,
    ) async {
      final now = DateTime.now();
      // Order with a shipment in inspection period
      final order = OrderModel(
        id: 'order-track-001',
        orderNumber: 'TL-9001',
        productId: 'prod-jacket-1',
        buyerId: 'buyer-qa-1',
        sellerId: 'seller-1',
        productTitle: 'Vintage Denim Jacket',
        productImage: '',
        sellerName: 'Ukay Thrift',
        buyerName: 'QA Buyer',
        buyerAvatar: '',
        status: OrderStatus.delivered,
        paymentMethod: PaymentMethod.paymongo,
        amount: 850.0,
        shippingFee: 80.0,
        platformFee: 17.0,
        total: 947.0,
        createdAt: now.subtract(const Duration(days: 2)),
        deliveryMethod: DeliveryMethod.standard,
        shippingAddress: 'Block 12, Sunflower St., Bucana, Davao City, 8000',
        deliveryPhone: '09171234567',
        shipment: ShipmentModel(
          id: 'ship-001',
          orderId: 'order-track-001',
          deliveryStatus: DeliveryStatus.inspectionPeriod,
          deliveryMethod: 'freelance_rider',
          riderName: 'Juan Dela Cruz',
          riderPhone: '09181234567',
          vehicleType: 'motorcycle',
          inspectionStartedAt: now,
          inspectionExpiresAt: now.add(const Duration(hours: 24)),
        ),
      );

      bool confirmedReceived = false;

      await tester.pumpWidget(
        MaterialApp(
          home: _OrderTrackingHarness(
            order: order,
            onConfirmReceived: () => confirmedReceived = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify order details displayed
      expect(find.text('Track Order #TL-9001'), findsOneWidget);
      expect(find.text('Vintage Denim Jacket'), findsOneWidget);
      expect(find.text('Status: Inspection period'), findsOneWidget);
      expect(find.text('Total: ${formatCurrency(947.0)}'), findsOneWidget);

      // Verify inspection UI is shown
      expect(find.text('Inspection Period'), findsOneWidget);
      expect(find.text('Confirm Item Received'), findsOneWidget);

      // Confirm inspection is inspecting state
      expect(order.isInspecting, isTrue);
      expect(order.isTrackable, isTrue);
      expect(order.isCompleted, isFalse);

      // Buyer confirms item received
      await tester.ensureVisible(
          find.byKey(const Key('tracking-confirm-received')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracking-confirm-received')));
      await tester.pumpAndSettle();

      expect(confirmedReceived, isTrue);
      expect(
        find.text('Order Completed! Thank you for shopping.'),
        findsOneWidget,
      );
    });

    qaIntegrationTest(
        'ShipmentModel rider visibility rules enforce buyer privacy correctly', (
      tester,
    ) async {
      // Active rider during delivery
      final activeShipment = ShipmentModel(
        id: 'ship-active',
        orderId: 'order-1',
        deliveryStatus: DeliveryStatus.outForDelivery,
        deliveryMethod: 'freelance_rider',
        riderName: 'Pedro Penduko Santos',
        riderPhone: '09171234567',
        vehicleType: 'motorcycle',
      );

      expect(activeShipment.hasRider, isTrue);
      expect(activeShipment.isLocalRider, isTrue);
      expect(activeShipment.hasActiveRider, isTrue);
      expect(activeShipment.shouldShowBuyerRiderInfo, isTrue);
      expect(activeShipment.isRiderContactVisibleToBuyer, isTrue);
      expect(activeShipment.buyerRiderDisplayName(), 'Pedro Penduko Santos');
      expect(activeShipment.buyerRiderPhone(), '0917 123 4567');
      expect(activeShipment.vehicleLabel, 'Motorcycle');

      // Privacy-masked rider name for legacy display
      expect(activeShipment.buyerRiderName(), 'Pedro S.');

      // Completed delivery — rider info hidden
      final completedShipment = ShipmentModel(
        id: 'ship-done',
        orderId: 'order-1',
        deliveryStatus: DeliveryStatus.completed,
        deliveryMethod: 'freelance_rider',
        riderName: 'Pedro Penduko Santos',
        riderPhone: '09171234567',
      );

      expect(completedShipment.hasActiveRider, isFalse);
      expect(completedShipment.shouldShowBuyerRiderInfo, isFalse);
      expect(completedShipment.isRiderContactVisibleToBuyer, isFalse);

      // Official courier (not local rider)
      final courierShipment = ShipmentModel(
        id: 'ship-courier',
        orderId: 'order-2',
        deliveryStatus: DeliveryStatus.outForDelivery,
        deliveryMethod: 'lbc_express',
        riderName: 'LBC Driver',
        riderPhone: '09181234567',
      );

      expect(courierShipment.isLocalRider, isFalse);
      expect(courierShipment.isOfficialCourier, isTrue);
      expect(courierShipment.hasActiveRider, isFalse);
      expect(courierShipment.shouldShowBuyerRiderInfo, isFalse);
    });

    qaIntegrationTest(
        'delivery failure reasons surface human-readable summaries', (
      tester,
    ) async {
      // Known failure reason
      final failedShipment = ShipmentModel(
        id: 'ship-fail',
        orderId: 'order-1',
        deliveryStatus: DeliveryStatus.deliveryFailed,
        deliveryFailureReason: DeliveryFailureReason.buyerUnavailable,
      );

      expect(failedShipment.isFailed, isTrue);
      expect(failedShipment.deliveryFailureSummary, 'Buyer unavailable');

      // 'Other' reason with custom details
      final otherFailed = ShipmentModel(
        id: 'ship-fail-2',
        orderId: 'order-2',
        deliveryStatus: DeliveryStatus.deliveryFailed,
        deliveryFailureReason: DeliveryFailureReason.other,
        deliveryFailureDetails: 'Gate was locked, no one answered calls.',
      );

      expect(otherFailed.deliveryFailureSummary,
          'Gate was locked, no one answered calls.');

      // 'Other' reason without custom details
      final otherNoDetail = ShipmentModel(
        id: 'ship-fail-3',
        orderId: 'order-3',
        deliveryStatus: DeliveryStatus.deliveryFailed,
        deliveryFailureReason: DeliveryFailureReason.other,
        deliveryFailureDetails: '',
      );

      expect(otherNoDetail.deliveryFailureSummary, 'Other');

      // No failure
      final healthyShipment = ShipmentModel(
        id: 'ship-ok',
        orderId: 'order-4',
        deliveryStatus: DeliveryStatus.outForDelivery,
      );

      expect(healthyShipment.deliveryFailureSummary, isNull);
    });

    qaIntegrationTest(
        'OrderModel status flags correctly classify order lifecycle stages', (
      tester,
    ) async {
      // Payment pending → buyer needs to pay
      final pendingOrder = OrderModel(
        id: 'order-pend',
        orderNumber: 'TL-1001',
        productId: 'prod-1',
        buyerId: 'b-1',
        sellerId: 's-1',
        productTitle: 'Jacket',
        productImage: '',
        sellerName: 'Seller',
        buyerName: 'Buyer',
        buyerAvatar: '',
        amount: 500,
        shippingFee: 80,
        platformFee: 10,
        total: 590,
        status: OrderStatus.paymentPending,
        paymentMethod: PaymentMethod.unpaid,
        deliveryMethod: DeliveryMethod.standard,
        shippingAddress: 'Davao City',
        createdAt: DateTime.now(),
      );

      expect(pendingOrder.isPaymentPending, isTrue);
      expect(pendingOrder.needsBuyerPayment, isTrue);
      expect(pendingOrder.showsInPurchaseHistory, isFalse);
      expect(pendingOrder.isSellerVisible, isFalse);

      // Auction obligation — payment pending shows as awaiting payment
      final auctionOrder = pendingOrder.copyWith(
        auctionId: 'auc-001',
        source: 'auction',
      );
      expect(auctionOrder.isAuctionObligation, isTrue);
      expect(auctionOrder.showsAsAwaitingPayment, isTrue);

      // Preparing → paid, now visible to seller as "To ship"
      final preparingOrder = pendingOrder.copyWith(
        status: OrderStatus.preparing,
        paymentMethod: PaymentMethod.paymongo,
        paymentStatus: 'paid',
      );
      expect(preparingOrder.isPaymentPending, isFalse);
      expect(preparingOrder.showsInPurchaseHistory, isTrue);
      expect(preparingOrder.isSellerVisible, isTrue);
      expect(preparingOrder.isToShip, isTrue);
      expect(preparingOrder.isInTransit, isFalse);

      // Completed order
      final completedOrder = pendingOrder.copyWith(
        status: OrderStatus.completed,
        paymentStatus: 'paid',
      );
      expect(completedOrder.isCompleted, isTrue);
      expect(completedOrder.isToShip, isFalse);
      expect(completedOrder.isTrackable, isFalse);
      expect(completedOrder.showsInPurchaseHistory, isTrue);

      // Failed/Cancelled checkout
      final cancelledOrder = pendingOrder.copyWith(
        status: OrderStatus.cancelled,
        paymentStatus: 'failed',
      );
      expect(cancelledOrder.isFailedCheckout, isTrue);
      expect(cancelledOrder.showsInPurchaseHistory, isFalse);

      // Address validation
      final addressOrder = pendingOrder.copyWith(
        shippingAddress: 'Block 12, Davao City',
        deliveryPhone: '09171234567',
        addressMissing: false,
      );
      expect(addressOrder.hasValidDeliveryAddress, isTrue);

      final missingAddressOrder = pendingOrder.copyWith(
        shippingAddress: '',
        deliveryPhone: '',
        addressMissing: true,
      );
      expect(missingAddressOrder.hasValidDeliveryAddress, isFalse);
    });

    qaIntegrationTest(
        'DeliveryStatus progression flags match expected state transitions', (
      tester,
    ) async {
      // Preparing states
      expect(DeliveryStatus.sellerPreparing.isPreparing, isTrue);
      expect(DeliveryStatus.riderAssigned.isPreparing, isTrue);
      expect(DeliveryStatus.readyForPickup.isPreparing, isTrue);
      expect(DeliveryStatus.pickedUp.isPreparing, isFalse);

      // In transit states
      expect(DeliveryStatus.pickedUp.isInTransit, isTrue);
      expect(DeliveryStatus.outForDelivery.isInTransit, isTrue);
      expect(DeliveryStatus.awaitingDeliveryVerification.isInTransit, isTrue);
      expect(DeliveryStatus.deliveryVerified.isInTransit, isFalse);

      // Allows rider updates only before handoff
      expect(DeliveryStatus.sellerPreparing.allowsRiderUpdates, isTrue);
      expect(DeliveryStatus.pickedUp.allowsRiderUpdates, isTrue);
      expect(DeliveryStatus.outForDelivery.allowsRiderUpdates, isFalse);

      // Inspecting states
      expect(DeliveryStatus.deliveryVerified.isInspecting, isTrue);
      expect(DeliveryStatus.inspectionPeriod.isInspecting, isTrue);
      expect(DeliveryStatus.completed.isInspecting, isFalse);

      // fromDb parsing
      expect(DeliveryStatus.fromDb('out_for_delivery'),
          DeliveryStatus.outForDelivery);
      expect(DeliveryStatus.fromDb('delivery_failed'),
          DeliveryStatus.deliveryFailed);
      expect(DeliveryStatus.fromDb(null), DeliveryStatus.sellerPreparing);
      expect(
          DeliveryStatus.fromDb('garbage'), DeliveryStatus.sellerPreparing);
    });
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(QaReporter.printFinalReport);

  qaSection(QaTestType.integration, () {
    orderTrackingIntegrationTests();
  });
}
