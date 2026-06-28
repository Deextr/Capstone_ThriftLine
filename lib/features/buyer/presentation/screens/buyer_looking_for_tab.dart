import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/looking_for_card.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerLookingForTab extends StatefulWidget {
  const BuyerLookingForTab({super.key});

  @override
  State<BuyerLookingForTab> createState() => _BuyerLookingForTabState();
}

class _BuyerLookingForTabState extends State<BuyerLookingForTab> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedFilter = 'Recently Posted';
  final List<String> _filters = ['Recently Posted', 'Most Popular', 'Nearest', 'Highest Budget'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataProvider>();
    final auth = context.watch<AuthProvider>();
    final buyerId = auth.user?.id ?? 'buyer_maya';
    final myPosts = data.lookingForPosts.where((p) => p.buyerId == buyerId).toList();
    final browsePosts = data.lookingForPosts;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: DefaultTabController(
            length: 2,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    floating: true,
                    pinned: true,
                    snap: false,
                    title: Text('Looking For', style: AppTypography.heading),
                    backgroundColor: AppColors.surface,
                    elevation: innerBoxIsScrolled ? 4 : 0,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.filter_list, color: AppColors.textPrimary),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.search, color: AppColors.textPrimary),
                        onPressed: () {},
                      ),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: _filters.map((filter) {
                                final isSelected = _selectedFilter == filter;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(
                                      filter,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : AppColors.textPrimary,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (bool selected) {
                                      setState(() {
                                        _selectedFilter = filter;
                                      });
                                    },
                                    backgroundColor: AppColors.surface,
                                    selectedColor: AppColors.primary,
                                    checkmarkColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(
                                        color: isSelected ? AppColors.primary : AppColors.border,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          TabBar(
                            controller: _tab,
                            labelColor: AppColors.primary,
                            indicatorColor: AppColors.primary,
                            unselectedLabelColor: AppColors.textSecondary,
                            tabs: const [Tab(text: 'Browse Requests'), Tab(text: 'My Requests')],
                          ),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tab,
                children: [
                  _buildList(browsePosts, true),
                  _buildList(myPosts, false),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 80.0),
          child: FloatingActionButton.extended(
            onPressed: () => _showPostSheet(context),
            icon: const Icon(Icons.edit),
            label: const Text('Post Request', style: TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<LookingForModel> posts, bool isSellerView) {
    if (posts.isEmpty) {
      return EmptyState(
        icon: Icons.post_add,
        title: 'No requests found',
        message: 'Be the first to post what you are looking for!',
        actionLabel: 'Post a Request',
        onAction: () => _showPostSheet(context),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), // extra padding for FAB
        itemCount: posts.length,
        itemBuilder: (_, i) {
          final post = posts[i];
          return LookingForCard(
            post: post,
            showRespondButton: isSellerView,
            onRespond: () => showThriftSnackBar(context, 'Response sent to ${post.buyerName}!'),
            onLike: () {
               setState(() {
                 // Mock like toggle behavior
               });
            },
          );
        },
      ),
    );
  }

  void _showPostSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final minCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final locCtrl = TextEditingController(text: 'Quezon City, Metro Manila');
    var category = ProductCategory.tops;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle for bottom sheet
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Create Request', style: AppTypography.heading),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Image Upload Placeholder
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.textSecondary),
                        const SizedBox(height: 8),
                        Text('Add Reference Image (Optional)', style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  ThriftTextField(label: 'What are you looking for?', controller: nameCtrl, hint: 'e.g. Vintage Levi\'s 501'),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<ProductCategory>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    items: ProductCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
                    onChanged: (v) => category = v!,
                  ),
                  const SizedBox(height: 16),
                  
                  ThriftTextField(
                    label: 'Description',
                    controller: descCtrl,
                    maxLines: 4,
                    hint: 'Describe the specific details, colors, or condition you want...',
                  ),
                  const SizedBox(height: 16),
                  
                  ThriftTextField(label: 'Preferred Size', controller: sizeCtrl, hint: 'e.g. M, 32, One Size'),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: ThriftTextField(
                          label: 'Budget Min (₱)',
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ThriftTextField(
                          label: 'Budget Max (₱)',
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  ThriftTextField(label: 'Your Location', controller: locCtrl),
                  const SizedBox(height: 40),
                  
                  ThriftButton(
                    label: 'Post Request',
                    onPressed: () {
                      if (nameCtrl.text.isEmpty) {
                        showThriftSnackBar(context, 'Please enter what you are looking for.');
                        return;
                      }
                      final auth = context.read<AuthProvider>();
                      final user = auth.user;
                      context.read<DataProvider>().addLookingFor(LookingForModel(
                        id: const Uuid().v4(),
                        buyerId: user?.id ?? 'buyer_maya',
                        buyerName: user?.displayName ?? 'Maya Santos',
                        buyerAvatar: 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(user?.displayName ?? 'Maya Santos')}&background=0D9488&color=fff&size=150',
                        title: nameCtrl.text,
                        description: descCtrl.text,
                        category: category,
                        budgetMin: double.tryParse(minCtrl.text) ?? 0,
                        budgetMax: double.tryParse(maxCtrl.text) ?? 0,
                        size: sizeCtrl.text,
                        location: locCtrl.text,
                        createdAt: DateTime.now(),
                      ));
                      Navigator.pop(context);
                      showThriftSnackBar(context, 'Request posted successfully!');
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

