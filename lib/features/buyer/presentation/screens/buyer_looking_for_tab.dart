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
import '../../domain/looking_for_feed_query.dart';
import '../../domain/looking_for_lifecycle.dart';
import '../widgets/create_looking_for_sheet.dart';
import '../widgets/looking_for_browse_feed_skeleton.dart';
import '../widgets/looking_for_filter_sheet.dart';
import '../widgets/looking_for_tab_chrome.dart';
import '../widgets/report_looking_for_sheet.dart';

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
  LookingForSort _sort = LookingForSort.recentlyPosted;
  LookingForFeedFilters _filters = const LookingForFeedFilters();

  @override
  void initState() {
    super.initState();
    if (!widget.sellerWorkspace) {
      _tab = TabController(length: 3, vsync: this);
      _tab!.addListener(() {
        if (!_tab!.indexIsChanging && mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tab?.dispose();
    super.dispose();
  }

  TabBar _lookingForTabBar() {
    return TabBar(
      controller: _tab,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: AppColors.primaryDark,
      indicatorColor: AppColors.primary,
      indicatorWeight: 2.5,
      labelStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: AppTypography.caption.copyWith(
        fontWeight: FontWeight.w500,
      ),
      unselectedLabelColor: AppColors.textSecondary,
      dividerColor: AppColors.border,
      tabs: const [
        Tab(text: 'Browse'),
        Tab(text: 'My active'),
        Tab(text: 'Inactive'),
      ],
    );
  }

  Future<void> _openCreateSheet() async {
    final looking = context.read<LookingForController>();
    if (looking.isPostingRestricted) {
      showThriftSnackBar(
        context,
        looking.postingRestrictionMessage ??
            "You can't post Looking For requests right now.",
        isError: true,
      );
      return;
    }
    final created = await CreateLookingForSheet.show(
      context,
      controller: looking,
    );
    if (!created || !mounted) return;
    await looking.refresh();
    if (!mounted) return;
    showThriftSnackBar(context, 'Request posted.');
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

  Future<void> _repost(LookingForModel post) async {
    final looking = context.read<LookingForController>();
    final saved = await CreateLookingForSheet.show(
      context,
      controller: looking,
      existing: post,
      repost: true,
    );
    if (!saved || !mounted) return;
    await looking.refresh();
    if (!mounted) return;
    _tab?.animateTo(1);
    showThriftSnackBar(context, 'Request posted again.');
  }

  Future<void> _report(LookingForModel post) async {
    final choice = await ReportLookingForSheet.show(context);
    if (choice == null || !mounted) return;
    final error = await context.read<LookingForController>().reportPost(
      postId: post.id,
      reason: choice.reason,
      details: choice.details,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Report sent. An admin will review it.');
  }

  Future<void> _close(LookingForModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as fulfilled?'),
        content: const Text(
          'Sellers will no longer see this as an active request. You can still '
          'find it under Inactive Requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark fulfilled'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await context.read<LookingForController>().closePost(
      post.id,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Request marked as fulfilled.');
  }

  Future<void> _delete(LookingForModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete request?'),
        content: const Text(
          'This will remove this Looking For request from your list.',
        ),
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
    showThriftSnackBar(context, 'Request removed from your list.');
  }

  @override
  Widget build(BuildContext context) {
    final looking = context.watch<LookingForController>();
    final browsePosts = _queryPosts(
      looking.browsePosts,
      section: _LookingSection.browse,
    );
    final activePosts = _queryPosts(
      looking.myActivePosts,
      section: _LookingSection.active,
    );
    final inactivePosts = _queryPosts(
      looking.myInactivePosts,
      section: _LookingSection.inactive,
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          bottom: false,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              final notice = widget.sellerWorkspace
                  ? null
                  : looking.postingRestrictionMessage;
              return [
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  title: Text(
                    widget.sellerWorkspace ? 'Buyer requests' : 'Looking For',
                    style: AppTypography.heading,
                  ),
                  backgroundColor: AppColors.surface,
                  surfaceTintColor: Colors.transparent,
                  elevation: innerBoxIsScrolled ? 0.5 : 0,
                ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: LookingForWorkspaceIntro(
                      sellerWorkspace: widget.sellerWorkspace,
                    ),
                  ),
                ),
                if (notice != null)
                  SliverToBoxAdapter(
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: LookingForRestrictionBanner(message: notice),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: LookingForFeedToolbar(
                      sort: _sort,
                      filters: _filters,
                      onSortChanged: (value) => setState(() => _sort = value),
                      onOpenFilters: () => _openFilters(
                        showInactiveStatus:
                            !widget.sellerWorkspace &&
                            (_tab?.index ?? 0) == 2,
                      ),
                      onClearFilters: () =>
                          setState(() => _filters = const LookingForFeedFilters()),
                    ),
                  ),
                ),
                if (!widget.sellerWorkspace && _tab != null)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _LookingForTabBarDelegate(
                      tabBar: _lookingForTabBar(),
                    ),
                  ),
              ];
            },
            body: widget.sellerWorkspace || _tab == null
                ? _buildList(
                    looking,
                    browsePosts,
                    sourceCount: looking.browsePosts.length,
                    section: _LookingSection.browse,
                    showRespond: true,
                  )
                : TabBarView(
                    controller: _tab,
                    children: [
                      _buildList(
                        looking,
                        browsePosts,
                        sourceCount: looking.browsePosts.length,
                        section: _LookingSection.browse,
                        showShare: true,
                      ),
                      _buildList(
                        looking,
                        activePosts,
                        sourceCount: looking.myActivePosts.length,
                        section: _LookingSection.active,
                        showShare: true,
                      ),
                      _buildList(
                        looking,
                        inactivePosts,
                        sourceCount: looking.myInactivePosts.length,
                        section: _LookingSection.inactive,
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
                      onPressed: looking.isPostingRestricted
                          ? null
                          : _openCreateSheet,
                      icon: const Icon(Icons.edit),
                      label: const Text(
                        'Post a request',
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

  List<LookingForModel> _queryPosts(
    List<LookingForModel> source, {
    required _LookingSection section,
  }) {
    return queryLookingForPosts(
      source,
      sort: _sort,
      filters: _filters,
      applyInactiveStatus: section == _LookingSection.inactive,
    );
  }

  Future<void> _openFilters({required bool showInactiveStatus}) async {
    await LookingForFilterSheet.show(
      context,
      initial: _filters,
      showInactiveStatus: showInactiveStatus,
      onApply: (value) => setState(() => _filters = value),
    );
  }

  Widget _buildList(
    LookingForController looking,
    List<LookingForModel> posts, {
    required int sourceCount,
    required _LookingSection section,
    bool showRespond = false,
    bool showShare = false,
  }) {
    if (looking.isLoading && looking.posts.isEmpty) {
      if (section == _LookingSection.browse) {
        return const LookingForBrowseFeedSkeleton();
      }
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
    if (posts.isEmpty &&
        sourceCount > 0 &&
        (_filters.hasAnyFilter || _sort != LookingForSort.recentlyPosted)) {
      return EmptyState(
        icon: Icons.filter_list_off,
        title: 'No matching requests',
        message:
            'Try adjusting filters or sort. You can reset everything from the toolbar.',
        actionLabel: 'Clear filters',
        onAction: () => setState(() {
          _filters = const LookingForFeedFilters();
          _sort = LookingForSort.recentlyPosted;
        }),
      );
    }
    if (lookingForShowsEmpty(
      isLoading: looking.isLoading,
      postCount: posts.length,
    )) {
      return _empty(section);
    }

    final me = looking.auth.user?.id;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final useFeed = section == _LookingSection.browse;
    final header = _sectionHeader(section, posts.length);

    return RefreshIndicator(
      onRefresh: looking.refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 96.0 + bottomInset),
        itemCount: posts.length + (header == null ? 0 : 1),
        itemBuilder: (_, i) {
          if (header != null && i == 0) return header;
          final postIndex = i - (header == null ? 0 : 1);
          final post = posts[postIndex];
          final isOwn = me != null && me == post.buyerId;
          final ownerSection =
              !widget.sellerWorkspace &&
              (section == _LookingSection.active ||
                  section == _LookingSection.inactive);
          return LookingForCard(
            post: post,
            layout: useFeed ? LookingForCardLayout.feed : null,
            showShare: showShare && post.showInBrowse,
            showRespondButton: showRespond && !isOwn && post.showInBrowse,
            showOwnerActions: ownerSection && isOwn,
            showReport: !isOwn && post.showInBrowse,
            onTap: () => _openPost(post),
            onShare: () => _share(post),
            onRespond: () => _iHaveThis(post),
            onEdit: () => _edit(post),
            onClose: () => _close(post),
            onDelete: () => _delete(post),
            onRepost: () => _repost(post),
            onReport: () => _report(post),
          );
        },
      ),
    );
  }

  Widget? _sectionHeader(_LookingSection section, int count) {
    if (section == _LookingSection.browse) return null;
    return switch (section) {
      _LookingSection.active => LookingForListSectionHeader(
        title: 'Active requests',
        subtitle:
            'These are visible to sellers until they expire or you mark them fulfilled.',
        count: count,
      ),
      _LookingSection.inactive => LookingForListSectionHeader(
        title: 'Past requests',
        subtitle: 'Expired or fulfilled requests. Repost to ask again.',
        count: count,
      ),
      _ => null,
    };
  }

  Widget _empty(_LookingSection section) {
    final restricted = context.read<LookingForController>().isPostingRestricted;
    return switch (section) {
      _LookingSection.browse => EmptyState(
        icon: Icons.search,
        title: widget.sellerWorkspace
            ? 'No buyer requests yet'
            : 'No requests yet',
        message: widget.sellerWorkspace
            ? 'When buyers post what they are looking for, they will show up here.'
            : 'Looking For requests from the community will appear here.',
        actionLabel: widget.sellerWorkspace || restricted
            ? null
            : 'Post a request',
        onAction: widget.sellerWorkspace || restricted
            ? null
            : _openCreateSheet,
      ),
      _LookingSection.active => EmptyState(
        icon: Icons.post_add_outlined,
        title: "You don't have any active requests.",
        message: restricted
            ? context.read<LookingForController>().postingRestrictionMessage!
            : 'Post a request so sellers can help you find it.',
        actionLabel: restricted ? null : 'Post a request',
        onAction: restricted ? null : _openCreateSheet,
      ),
      _LookingSection.inactive => const EmptyState(
        icon: Icons.history,
        title: 'No inactive requests yet.',
        message: 'Expired requests will appear here.',
      ),
    };
  }
}

enum _LookingSection { browse, active, inactive }

class _LookingForTabBarDelegate extends SliverPersistentHeaderDelegate {
  _LookingForTabBarDelegate({required this.tabBar});

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: AppColors.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _LookingForTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
