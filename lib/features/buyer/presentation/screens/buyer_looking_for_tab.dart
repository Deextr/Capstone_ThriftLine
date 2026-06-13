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
import '../../../../widgets/bid_card.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';

class BuyerLookingForTab extends StatefulWidget {
  const BuyerLookingForTab({super.key});

  @override
  State<BuyerLookingForTab> createState() => _BuyerLookingForTabState();
}

class _BuyerLookingForTabState extends State<BuyerLookingForTab> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
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
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: Row(
                children: [
                  Text('Looking For', style: AppTypography.heading),
                  const Spacer(),
                  FloatingActionButton.small(
                    onPressed: () => _showPostSheet(context),
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              tabs: const [Tab(text: 'My Requests'), Tab(text: 'Browse Requests')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _list(myPosts, false),
                  _list(browsePosts, true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List posts, bool sellerView) {
    if (posts.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_border,
        title: 'No requests yet',
        message: 'Post what you\'re looking for and let sellers find you!',
        actionLabel: 'Post Request',
        onAction: () => _showPostSheet(context),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: posts.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: LookingForCard(
            post: posts[i],
            showRespondButton: sellerView,
            onRespond: () => showThriftSnackBar(context, 'Response sent!'),
          ),
        ),
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

    ThriftBottomSheet.show(
      context,
      title: 'Post Request',
      child: Column(
        children: [
          ThriftTextField(label: 'Item name', controller: nameCtrl, hint: 'e.g. Y2K butterfly top'),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProductCategory>(
            value: category,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: ProductCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.label))).toList(),
            onChanged: (v) => category = v!,
          ),
          const SizedBox(height: 12),
          ThriftTextField(label: 'Description', controller: descCtrl, maxLines: 3),
          const SizedBox(height: 12),
          ThriftTextField(label: 'Size', controller: sizeCtrl),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: ThriftTextField(label: 'Budget Min', controller: minCtrl, keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: ThriftTextField(label: 'Budget Max', controller: maxCtrl, keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 12),
          ThriftTextField(label: 'Preferred location', controller: locCtrl),
          const SizedBox(height: 20),
          ThriftButton(
            label: 'Post Request',
            onPressed: () {
              final auth = context.read<AuthProvider>();
              final user = auth.user;
              context.read<DataProvider>().addLookingFor(LookingForModel(
                id: const Uuid().v4(),
                buyerId: user?.id ?? 'buyer_maya',
                buyerName: user?.displayName ?? 'Maya Santos',
                buyerAvatar: 'https://i.pravatar.cc/150?u=${user?.username ?? "maya"}',
                title: 'Looking for: ${nameCtrl.text}',
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
        ],
      ),
    );
  }
}
