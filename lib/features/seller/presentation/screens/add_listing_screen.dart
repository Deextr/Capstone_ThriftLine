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

  final List<String> _imageUrls = [];

  static const _mockPhotoOptions = [
    'https://images.unsplash.com/photo-1554568218-0f1715e72254?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1516762689617-e1cffcef479d?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1595950653106-6c9ebd614d3a?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1624378439575-d8705ad7ae80?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1584916201218-f4242ceb4809?auto=format&fit=crop&q=80&w=600&h=600',
  ];

  Color _getColorValue(String colorName) {
    switch (colorName) {
      case 'Black': return Colors.black;
      case 'White': return Colors.white;
      case 'Red': return Colors.red.shade600;
      case 'Blue': return Colors.blue.shade600;
      case 'Green': return Colors.green.shade600;
      case 'Yellow': return Colors.yellow.shade600;
      case 'Pink': return Colors.pink.shade300;
      case 'Purple': return Colors.purple.shade600;
      case 'Orange': return Colors.orange.shade600;
      case 'Brown': return Colors.brown.shade600;
      case 'Gray': return Colors.grey.shade500;
      case 'Navy': return const Color(0xFF1E3A8A);
      case 'Beige': return const Color(0xFFF5F5DC);
      case 'Cream': return const Color(0xFFFFFDD0);
      case 'Olive': return const Color(0xFF808000);
      default: return Colors.grey.shade300;
    }
  }

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
            Text('Tap photos to select them. First photo will be the cover.', style: AppTypography.caption),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 8,
              itemBuilder: (_, i) {
                final url = _mockPhotoOptions[i];
                final isAdded = _imageUrls.contains(url);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isAdded) {
                        _imageUrls.remove(url);
                      } else {
                        _imageUrls.add(url);
                      }
                    });
                  },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isAdded ? AppColors.primary : AppColors.border,
                        width: isAdded ? 2 : 1,
                      ),
                    ),
                    child: isAdded
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(url, fit: BoxFit.cover),
                              if (_imageUrls.indexOf(url) == 0) // Cover marker
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: const Text(
                                      'Cover',
                                      style: TextStyle(color: Colors.white, fontSize: 8),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(2),
                                  child: Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(i == 0 ? Icons.add_a_photo : Icons.add, color: AppColors.textHint, size: 20),
                              Text(i == 0 ? 'Cover' : 'Photo ${i + 1}', style: const TextStyle(fontSize: 9, color: AppColors.textHint)),
                            ],
                          ),
                  ),
                );
              },
            ),
          ],
        ),
      );

  Widget _detailsStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ThriftTextField(label: 'Product Name', controller: _nameCtrl),
            const SizedBox(height: 16),
            _selectorField(
              label: 'Category',
              value: _category.label,
              icon: Icons.category_outlined,
              onTap: () => _showCategoryPicker(context),
            ),
            const SizedBox(height: 16),
            Text('Condition', style: AppTypography.label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: ProductCondition.values.map((c) {
                final isSelected = _condition == c;
                return ChoiceChip(
                  label: Text(c.label),
                  selected: isSelected,
                  selectedColor: AppColors.primaryLight,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  ),
                  onSelected: (_) => setState(() => _condition = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            ThriftTextField(label: 'Brand', controller: _brandCtrl),
            const SizedBox(height: 16),
            ThriftTextField(label: 'Size', controller: _sizeCtrl),
            const SizedBox(height: 16),
            _selectorField(
              label: 'Color',
              value: _selectedColor,
              icon: Icons.palette_outlined,
              onTap: () => _showColorPicker(context),
            ),
            const SizedBox(height: 16),
            ThriftTextField(label: 'Material', controller: _materialCtrl),
            const SizedBox(height: 16),
            ThriftTextField(label: 'Description', controller: _descCtrl, maxLines: 4),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_descCtrl.text.length}/500',
                style: AppTypography.caption,
              ),
            ),
          ],
        ),
      );

  Widget _pricingStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selling Format', style: AppTypography.heading),
            Text('Choose how you want to sell your item', style: AppTypography.caption),
            const SizedBox(height: 16),
            Row(
              children: [
                _formatCard(SellingType.fixedPrice, 'Fixed Price', Icons.tag),
                const SizedBox(width: 8),
                _formatCard(SellingType.auction, 'Auction', Icons.gavel),
                const SizedBox(width: 8),
                _formatCard(SellingType.both, 'Both Formats', Icons.grid_view),
              ],
            ),
            const SizedBox(height: 24),
            if (_sellingType != SellingType.auction) ...[
              Text(
                _sellingType == SellingType.both ? 'Buy Now Details' : 'Pricing Details',
                style: AppTypography.subheading.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ThriftTextField(
                label: _sellingType == SellingType.both ? 'Buy Now Price (₱)' : 'Price (₱)',
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
            ],
            if (_sellingType != SellingType.fixedPrice) ...[
              Text('Bidding Details', style: AppTypography.subheading.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ThriftTextField(label: 'Starting Bid (₱)', controller: _startBidCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              _selectorField(
                label: 'Auction Duration',
                value: '$_bidDays days',
                icon: Icons.today_outlined,
                onTap: () => _showBidDurationPicker(context),
              ),
              const SizedBox(height: 16),
              _selectorField(
                label: 'Minimum Bid Increment',
                value: '₱${_bidIncrement.toInt()}',
                icon: Icons.add_circle_outline_rounded,
                onTap: () => _showBidIncrementPicker(context),
              ),
            ],
          ],
        ),
      );

  Widget _formatCard(SellingType type, String label, IconData icon) {
    final isSelected = _sellingType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sellingType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectorField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textHint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontSize: 15),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCategoryPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Select Category',
      child: Column(
        children: ProductCategory.values.map((c) => ListTile(
          leading: Icon(Icons.sell_outlined, color: _category == c ? AppColors.primary : AppColors.textSecondary),
          title: Text(c.label, style: TextStyle(fontWeight: _category == c ? FontWeight.bold : FontWeight.normal)),
          trailing: _category == c ? const Icon(Icons.check, color: AppColors.primary) : null,
          onTap: () {
            setState(() => _category = c);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Select Color',
      child: Column(
        children: _colors.map((c) => ListTile(
          leading: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getColorValue(c),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
          ),
          title: Text(c, style: TextStyle(fontWeight: _selectedColor == c ? FontWeight.bold : FontWeight.normal)),
          trailing: _selectedColor == c ? const Icon(Icons.check, color: AppColors.primary) : null,
          onTap: () {
            setState(() => _selectedColor = c);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _showBidDurationPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Auction Duration',
      child: Column(
        children: [1, 3, 5, 7].map((d) => ListTile(
          leading: Icon(Icons.today, color: _bidDays == d ? AppColors.primary : AppColors.textSecondary),
          title: Text('$d days', style: TextStyle(fontWeight: _bidDays == d ? FontWeight.bold : FontWeight.normal)),
          trailing: _bidDays == d ? const Icon(Icons.check, color: AppColors.primary) : null,
          onTap: () {
            setState(() => _bidDays = d);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  void _showBidIncrementPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Minimum Bid Increment',
      child: Column(
        children: [10.0, 20.0, 50.0, 100.0].map((d) => ListTile(
          leading: Icon(Icons.add_circle_outline, color: _bidIncrement == d ? AppColors.primary : AppColors.textSecondary),
          title: Text('₱${d.toInt()}', style: TextStyle(fontWeight: _bidIncrement == d ? FontWeight.bold : FontWeight.normal)),
          trailing: _bidIncrement == d ? const Icon(Icons.check, color: AppColors.primary) : null,
          onTap: () {
            setState(() => _bidIncrement = d);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }

  Widget _deliveryStep() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(title: const Text('Standard Shipping'), value: _standardShip, onChanged: (v) => setState(() => _standardShip = v)),
            SwitchListTile(title: const Text('Express Shipping'), value: _expressShip, onChanged: (v) => setState(() => _expressShip = v)),
            SwitchListTile(title: const Text('Meet-up'), value: _meetup, onChanged: (v) => setState(() => _meetup = v)),
            SwitchListTile(title: const Text('Free Shipping'), value: _freeShipping, onChanged: (v) => setState(() => _freeShipping = v)),
            ThriftTextField(label: 'Item Location', controller: _locationCtrl),
          ],
        ),
      );

  Widget _reviewStep() {
    final formatLabel = switch (_sellingType) {
      SellingType.fixedPrice => 'Buy Now Only',
      SellingType.auction => 'Auction Only',
      SellingType.both => 'Auction + Buy Now',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review Listing', style: AppTypography.heading),
          Text('Double check the details before posting', style: AppTypography.caption),
          const SizedBox(height: 16),
          ThriftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_imageUrls.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_imageUrls.first, height: 180, width: double.infinity, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  _brandCtrl.text.isEmpty ? 'Unbranded' : _brandCtrl.text,
                  style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
                Text(
                  _nameCtrl.text.isEmpty ? 'New Listing' : _nameCtrl.text,
                  style: AppTypography.subheading.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                _reviewRow('Format', formatLabel),
                if (_sellingType != SellingType.auction && _priceCtrl.text.isNotEmpty)
                  _reviewRow('Buy Now Price', '₱${_priceCtrl.text}'),
                if (_sellingType != SellingType.fixedPrice) ...[
                  if (_startBidCtrl.text.isNotEmpty) _reviewRow('Starting Bid', '₱${_startBidCtrl.text}'),
                  _reviewRow('Bid Increment', '₱${_bidIncrement.toInt()}'),
                  _reviewRow('Bid Duration', '$_bidDays days'),
                ],
                _reviewRow('Category', _category.label),
                _reviewRow('Condition', _condition.label),
                if (_sizeCtrl.text.isNotEmpty) _reviewRow('Size', _sizeCtrl.text),
                _reviewRow('Color', _selectedColor),
                if (_materialCtrl.text.isNotEmpty) _reviewRow('Material', _materialCtrl.text),
                if (_locationCtrl.text.isNotEmpty) _reviewRow('Location', _locationCtrl.text),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                Text('Description', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  _descCtrl.text.isEmpty ? 'No description provided.' : _descCtrl.text,
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

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
      description: _descCtrl.text.isEmpty
          ? 'Pre-loved ${_nameCtrl.text.isEmpty ? 'item' : _nameCtrl.text} in great condition. Carefully curated and ready for a new home. Message seller for more details or measurements.'
          : _descCtrl.text,
      price: double.tryParse(_priceCtrl.text) ?? double.tryParse(_startBidCtrl.text) ?? 0,
      category: _category,
      condition: _condition,
      imageUrls: _imageUrls.isNotEmpty ? _imageUrls : ['https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&q=80&w=600&h=600'],
      size: _sizeCtrl.text.isEmpty ? null : _sizeCtrl.text,
      brand: _brandCtrl.text.isEmpty ? null : _brandCtrl.text,
      color: _selectedColor,
      material: _materialCtrl.text.isEmpty ? null : _materialCtrl.text,
      location: _locationCtrl.text.isEmpty ? null : _locationCtrl.text,
      createdAt: DateTime.now(),
      sellingType: _sellingType,
      startingBid: double.tryParse(_startBidCtrl.text),
      currentBid: _sellingType == SellingType.auction ? double.tryParse(_startBidCtrl.text) : null,
      bidEndTime: _sellingType != SellingType.fixedPrice ? DateTime.now().add(Duration(days: _bidDays)) : null,
      bidIncrement: _bidIncrement,
      buyNowEnabled: _sellingType == SellingType.both,
    ));
    showThriftSnackBar(context, 'Listing published!');
    context.go(RouteNames.sellerHome);
  }
}
