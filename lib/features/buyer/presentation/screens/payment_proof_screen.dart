import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class PaymentProofScreen extends StatefulWidget {
  const PaymentProofScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<PaymentProofScreen> createState() => _PaymentProofScreenState();
}

class _PaymentProofScreenState extends State<PaymentProofScreen> {
  final _refCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _refCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment Proof'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Column(
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 32),
                      SizedBox(height: 8),
                      Text('Tap to upload screenshot'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ThriftTextField(label: 'Reference number', controller: _refCtrl),
                const SizedBox(height: 12),
                ThriftTextField(label: 'Amount paid', controller: _amountCtrl, keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('Date: ${_date.toString().split(' ').first}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
                const Spacer(),
                ThriftButton(
                  label: 'Submit Proof',
                  onPressed: () {
                    context.read<DataProvider>().submitPaymentProof(widget.orderId);
                    showThriftSnackBar(context, 'Payment proof submitted!');
                    context.go(RouteNames.buyerHome);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
