import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../widgets/looking_for_card.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../chat/presentation/widgets/share_looking_for_sheet.dart';
import '../../controllers/looking_for_controller.dart';
import '../widgets/create_looking_for_sheet.dart';

class BuyerLookingForTab extends StatefulWidget {
  const BuyerLookingForTab({super.key, this.sellerWorkspace = false});

  /// Seller workspace: browse buyer requests and use I Have This. No create FAB.
  final bool sellerWorkspace;

  @override
  State<BuyerLookingForTab> createState() => _BuyerLookingForTabState();
}

class _BuyerLookingForTabState extends State<BuyerLookingForTab>
    with SingleTickerProviderStateMixin {
  TabController? _tab;
  String _selectedFilter = 'Recently Posted';
  final List<String> _filters = [
    'Recently Posted',
    'Most Popular',
    'Highest Budget',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.sellerWorkspace) {
      _tab = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  Future<void> _openCreateSheet() async {
    final looking = context.read<LookingForController>();
    final created = await CreateLookingForSheet.show(
      context,
      controller: looking,
    );
    if (!created || !mounted) return;
    await looking.refresh();
    if (!mounted) return;
    showThriftSnackBar(context, 'Request posted successfully!');
  }

  Future<void> _openPost(LookingForModel post) async {
    await context.push(RouteNames.lookingForPost(post.id));
    if (!mounted) return;
    await context.read<LookingForController>().refresh();
  }

  Future<void> _share(LookingForModel post) async {
    final looking = context.read<LookingForController>();
    final sent = await ShareLookingForSheet.show(
      context,
      post: post,
      controller: looking,
    );
    if (!sent || !mounted) return;
    showThriftSnackBar(context, 'Request shared with selected sellers.');
  }

  Future<void> _iHaveThis(LookingForModel post) async {
    final looking = context.read<LookingForController>();
    final result = await looking.sendIHaveThis(post);
    if (!mounted) return;
    if (!result.isOk) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Message sent to the buyer.');
    if (result.conversationId != null) {
      context.push(RouteNames.chatThread(result.conversationId!));
    }
  }

  Future<void> _edit(LookingForModel post) async {
    final looking = context.read<LookingForController>();
    final saved = await CreateLookingForSheet.show(
      context,
      controller: looking,
      existing: post,
    );
    if (!saved || !mounted) return;
    await looking.refresh();
    if (!mounted) return;
    showThriftSnackBar(context, 'Request updated.');
  }

  Future<void> _delete(LookingForModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this request?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await context.read<LookingForController>().deletePost(
      post.id,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Request deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final looking = context.watch<LookingForController>();
    final myPosts = _applyFilter(looking.myPosts);
    final browsePosts = _applyFilter(looking.posts);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  snap: false,
                  title: Text(
                    widget.sellerWorkspace ? 'Buyer Requests' : 'Looking For',
                    style: AppTypography.heading,
                  ),
                  backgroundColor: AppColors.surface,
                  elevation: innerBoxIsScrolled ? 4 : 0,
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(
                      widget.sellerWorkspace ? 56 : 112,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: _filters.map((filter) {
                              final isSelected = _selectedFilter == filter;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(
                                    filter,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    setState(() => _selectedFilter = filter);
                                  },
                                  backgroundColor: AppColors.surface,
                                  selectedColor: AppColors.primary,
                                  checkmarkColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        if (!widget.sellerWorkspace && _tab != null)
                          TabBar(
                            controller: _tab,
                            labelColor: AppColors.primary,
                            indicatorColor: AppColors.primary,
                            unselectedLabelColor: AppColors.textSecondary,
                            tabs: const [
                              Tab(text: 'Browse Requests'),
                              Tab(text: 'My Requests'),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: widget.sellerWorkspace || _tab == null
                ? _buildList(
                    looking,
                    browsePosts,
                    showRespond: true,
                    showShare: false,
                  )
                : TabBarView(
                    controller: _tab,
                    children: [
                      _buildList(
                        looking,
                        browsePosts,
                        showRespond: false,
                        showShare: true,
                      ),
                      _buildList(
                        looking,
                        myPosts,
                        showRespond: false,
                        showShare: true,
                        isMyTab: true,
                      ),
                    ],
                  ),
          ),
        ),
        floatingActionButton: widget.sellerWorkspace
            ? null
            : Builder(
                builder: (context) {
                  final bottomInset = MediaQuery.of(context).viewPadding.bottom;
                  return Padding(
                    padding: EdgeInsets.only(bottom: 80.0 + bottomInset),
                    child: FloatingActionButton.extended(
                      onPressed: _openCreateSheet,
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        'Post Request',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                },
              ),
      ),
    );
  }

  List<LookingForModel> _applyFilter(List<LookingForModel> posts) {
    final copy = [...posts];
    if (_selectedFilter == 'Most Popular') {
      copy.sort((a, b) => b.responseCount.compareTo(a.responseCount));
    } else if (_selectedFilter == 'Highest Budget') {
      copy.sort((a, b) => b.budgetMax.compareTo(a.budgetMax));
    } else {
      copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return copy;
  }

  Widget _buildList(
    LookingForController looking,
    List<LookingForModel> posts, {
    required bool showRespond,
    required bool showShare,
    bool isMyTab = false,
  }) {
    if (looking.isLoading && looking.posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (looking.errorMessage != null && looking.posts.isEmpty) {
      return ErrorState(
        message: looking.errorMessage!,
        onRetry: looking.refresh,
      );
    }
    if (lookingForShowsEmpty(
      isLoading: looking.isLoading,
      postCount: posts.length,
    )) {
      return EmptyState(
        icon: Icons.post_add,
        title: widget.sellerWorkspace
            ? 'No buyer requests yet'
            : isMyTab
            ? 'You have not posted a request'
            : 'No requests found',
        message: widget.sellerWorkspace
            ? 'When buyers post what they are looking for, they will show up here.'
            : isMyTab
            ? 'Post a request so sellers can help you find the item.'
            : 'Be the first to post what you are looking for!',
        actionLabel: widget.sellerWorkspace ? null : 'Post a Request',
        onAction: widget.sellerWorkspace ? null : _openCreateSheet,
      );
    }

    final me = looking.auth.user?.id;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return RefreshIndicator(
      onRefresh: looking.refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 96.0 + bottomInset),
        itemCount: posts.length,
        itemBuilder: (_, i) {
          final post = posts[i];
          final isOwn = me != null && me == post.buyerId;
          return LookingForCard(
            post: post,
            showShare: showShare,
            showRespondButton: showRespond && !isOwn,
            showOwnerActions: isOwn && !widget.sellerWorkspace,
            onTap: () => _openPost(post),
            onShare: () => _share(post),
            onRespond: () => _iHaveThis(post),
            onEdit: () => _edit(post),
            onDelete: () => _delete(post),
          );
        },
      ),
    );
  }
}
