import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/address_model.dart';
import '../../../../models/enums.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../profile/data/address_service.dart';

class PaymentDeliveryScreen extends StatefulWidget {
  const PaymentDeliveryScreen({super.key, required this.productId});

  final String productId;

  @override
  State<PaymentDeliveryScreen> createState() => _PaymentDeliveryScreenState();
}

class _PaymentDeliveryScreenState extends State<PaymentDeliveryScreen> {
  DeliveryMethod _delivery = DeliveryMethod.standard;
  PaymentMethod _payment = PaymentMethod.gcash;
  AddressModel? _address;
  bool _addressLoading = true;
  final _meetupLocation = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    try {
      final saved = await AddressService(context.read<SupabaseService>()).defaultAddress();
      if (!mounted) return;
      setState(() {
        _address = saved;
        _addressLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  @override
  void dispose() {
    _meetupLocation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final product = data.productById(widget.productId);
    if (product == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Not found')));

    final qty = int.tryParse(GoRouterState.of(context).uri.queryParameters['qty'] ?? '1') ?? 1;
    final subtotal = product.price * qty;
    final shipping = _delivery.fee;
    final platform = subtotal * 0.02;
    final total = subtotal + shipping + platform;
    final codDown = total * 0.2;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment & Delivery'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery Address', style: AppTypography.subheading),
                const SizedBox(height: 8),
                ThriftCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _addressLoading
                              ? 'Loading addressâ€¦'
                              : (_address?.formatted ??
                                  'No saved address yet. Add one before placing an order.'),
                          style: AppTypography.body,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await context.push(RouteNames.addresses);
                          if (mounted) await _loadAddress();
                        },
                        child: Text(_address == null ? 'Add' : 'Change'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Delivery Method', style: AppTypography.subheading),
                ...DeliveryMethod.values.map((d) => RadioListTile<DeliveryMethod>(
                  title: Text('${d.label} â€” ${formatCurrency(d.fee)}'),
                  value: d,
                  groupValue: _delivery,
                  onChanged: (v) => setState(() => _delivery = v!),
                )),
                if (_delivery == DeliveryMethod.meetup)
                  ThriftTextField(label: 'Meet-up location', controller: _meetupLocation, hint: 'e.g. SM North EDSA'),
                const SizedBox(height: 20),
                Text('Payment Method', style: AppTypography.subheading),
                ...PaymentMethod.values.map((p) => RadioListTile<PaymentMethod>(
                  title: Text(p.label),
                  value: p,
                  groupValue: _payment,
                  onChanged: (v) => setState(() => _payment = v!),
                )),
                if (_payment == PaymentMethod.cod)
                  ThriftCard(
                    child: Text(
                      '20% Downpayment Required: ${formatCurrency(codDown)}',
                      style: AppTypography.body.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 20),
                Text('Order Total', style: AppTypography.subheading),
                _row('Item price', formatCurrency(subtotal)),
                _row('Shipping fee', formatCurrency(shipping)),
                _row('Platform fee (2%)', formatCurrency(platform)),
                const Divider(),
                _row('Total', formatCurrency(total), bold: true),
                const SizedBox(height: 24),
                ThriftButton(
                  label: 'Place Order',
                  onPressed: () {
                    if (_delivery != DeliveryMethod.meetup && _address == null) {
                      showThriftSnackBar(context, 'Add a delivery address first.', isError: true);
                      return;
                    }
                    final auth = context.read<AuthProvider>();
                    final user = auth.user;
                    final order = data.createOrder(
                      product: product,
                      buyerId: auth.user?.id ?? '',
                      buyerName: user?.name ?? 'Buyer',
                      buyerAvatar: user?.avatarUrl ?? '',
                      quantity: qty,
                      delivery: _delivery,
                      payment: _payment,
                      address: _delivery == DeliveryMethod.meetup
                          ? _meetupLocation.text
                          : _address!.formatted,
                      size: product.size,
                    );
                    context.go('/order-confirm/${order.id}');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: bold ? AppTypography.subheading : AppTypography.body),
            Text(value, style: bold ? AppTypography.subheading.copyWith(color: AppColors.primary) : AppTypography.body),
          ],
        ),
      );
}
