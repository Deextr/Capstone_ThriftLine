import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/enums.dart';
import '../../../../models/product_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _pageController = PageController();
  int _step = 0;

  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _materialCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _startBidCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  ProductCategory _category = ProductCategory.tops;
  ProductCondition _condition = ProductCondition.good;
  SellingType _sellingType = SellingType.fixedPrice;
  String _selectedColor = 'Black';
  int _bidDays = 3;
  double _bidIncrement = 20;
  bool _standardShip = true;
  bool _expressShip = false;
  bool _meetup = false;
  bool _freeShipping = false;

  static const _colors = [
    'Black', 'White', 'Red', 'Blue', 'Green', 'Yellow', 'Pink', 'Purple',
    'Orange', 'Brown', 'Gray', 'Navy', 'Beige', 'Cream', 'Olive', 'Multicolor',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _sizeCtrl.dispose();
    _materialCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _startBidCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) {
          _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
          setState(() => _step--);
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text('Add Listing (${_step + 1}/5)'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_step > 0) {
                  _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  setState(() => _step--);
                } else {
                  context.pop();
                }
              },
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                LinearProgressIndicator(value: (_step + 1) / 5, color: AppColors.primary, backgroundColor: AppColors.primaryLight),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _photosStep(),
                      _detailsStep(),
                      _pricingStep(),
                      _deliveryStep(),
                      _reviewStep(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: ThriftButton(
                    label: _step == 4 ? 'Post Listing' : 'Continue',
                    onPressed: _next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photosStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photos', style: AppTypography.heading),
            Text('First photo will be the cover', style: AppTypography.caption),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: 8,
              itemBuilder: (_, i) => Container(
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: i == 0
                    ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo), Text('Cover', style: TextStyle(fontSize: 10))])
                    : const Icon(Icons.add, color: AppColors.textHint),
              ),
            ),
          ],
        ),
      );

  Widget _detailsStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ThriftTextField(label: 'Product Name', controller: _nameCtrl),
            const SizedBox(height: 12),
            DropdownButtonFormField<ProductCategory>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: ProductCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ProductCondition.values.map((c) => ChoiceChip(
                label: Text(c.label),
                selected: _condition == c,
                onSelected: (_) => setState(() => _condition = c),
              )).toList(),
            ),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Brand', controller: _brandCtrl),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Size', controller: _sizeCtrl),
            const SizedBox(height: 12),
            Text('Color', style: AppTypography.label),
            Wrap(
              spacing: 6,
              children: _colors.map((c) => GestureDetector(
                onTap: () => setState(() => _selectedColor = c),
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _selectedColor == c ? AppColors.primary : AppColors.border, width: 2),
                    color: AppColors.border,
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Material', controller: _materialCtrl),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Description', controller: _descCtrl, maxLines: 4),
            Align(alignment: Alignment.centerRight, child: Text('${_descCtrl.text.length}/500', style: AppTypography.caption)),
          ],
        ),
      );

  Widget _pricingStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selling Type', style: AppTypography.subheading),
            ...SellingType.values.map((t) => RadioListTile<SellingType>(
              title: Text(t.name),
              value: t,
              groupValue: _sellingType,
              onChanged: (v) => setState(() => _sellingType = v!),
            )),
            if (_sellingType != SellingType.auction) ThriftTextField(label: 'Price', controller: _priceCtrl, keyboardType: TextInputType.number),
            if (_sellingType != SellingType.fixedPrice) ...[
              ThriftTextField(label: 'Starting Bid', controller: _startBidCtrl, keyboardType: TextInputType.number),
              DropdownButtonFormField<int>(
                value: _bidDays,
                decoration: const InputDecoration(labelText: 'Bid Duration', border: OutlineInputBorder()),
                items: [1, 3, 5, 7].map((d) => DropdownMenuItem(value: d, child: Text('$d days'))).toList(),
                onChanged: (v) => setState(() => _bidDays = v!),
              ),
              DropdownButtonFormField<double>(
                value: _bidIncrement,
                decoration: const InputDecoration(labelText: 'Bid Increment', border: OutlineInputBorder()),
                items: [10.0, 20.0, 50.0, 100.0].map((d) => DropdownMenuItem(value: d, child: Text('₱${d.toInt()}'))).toList(),
                onChanged: (v) => setState(() => _bidIncrement = v!),
              ),
            ],
          ],
        ),
      );

  Widget _deliveryStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(title: const Text('Standard Shipping'), value: _standardShip, onChanged: (v) => setState(() => _standardShip = v)),
            SwitchListTile(title: const Text('Express Shipping'), value: _expressShip, onChanged: (v) => setState(() => _expressShip = v)),
            SwitchListTile(title: const Text('Meet-up'), value: _meetup, onChanged: (v) => setState(() => _meetup = v)),
            SwitchListTile(title: const Text('Free Shipping'), value: _freeShipping, onChanged: (v) => setState(() => _freeShipping = v)),
            ThriftTextField(label: 'Item location', controller: _locationCtrl),
          ],
        ),
      );

  Widget _reviewStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_nameCtrl.text.isEmpty ? 'Product Name' : _nameCtrl.text, style: AppTypography.heading),
              Text('${_category.label} • ${_condition.label}', style: AppTypography.caption),
              if (_priceCtrl.text.isNotEmpty) Text('₱${_priceCtrl.text}', style: AppTypography.subheading.copyWith(color: AppColors.primary)),
              Text(_descCtrl.text, style: AppTypography.body),
            ],
          ),
        ),
      );

  void _next() {
    if (_step < 4) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _step++);
      return;
    }
    final auth = context.read<AuthProvider>();
    final username = auth.username ?? 'vintagevibes_ph';
    context.read<DataProvider>().addProduct(ProductModel(
      id: 'prod_${const Uuid().v4().substring(0, 8)}',
      sellerUsername: username,
      sellerName: auth.displayName ?? 'Shop',
      sellerAvatar: 'https://i.pravatar.cc/150?u=$username',
      sellerVerified: true,
      title: _nameCtrl.text.isEmpty ? 'New Listing' : _nameCtrl.text,
      description: _descCtrl.text.isEmpty ? 'New listing' : _descCtrl.text,
      price: double.tryParse(_priceCtrl.text) ?? double.tryParse(_startBidCtrl.text) ?? 0,
      category: _category,
      condition: _condition,
      size: _sizeCtrl.text,
      brand: _brandCtrl.text,
      color: _selectedColor,
      material: _materialCtrl.text,
      location: _locationCtrl.text,
      createdAt: DateTime.now(),
      sellingType: _sellingType,
      startingBid: double.tryParse(_startBidCtrl.text),
      bidEndTime: _sellingType != SellingType.fixedPrice ? DateTime.now().add(Duration(days: _bidDays)) : null,
      bidIncrement: _bidIncrement,
    ));
    showThriftSnackBar(context, 'Listing published!');
    context.go(RouteNames.sellerHome);
  }
}
