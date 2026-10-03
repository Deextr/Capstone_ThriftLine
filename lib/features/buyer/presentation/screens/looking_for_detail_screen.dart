import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/empty_state.dart';
import '../../../../widgets/looking_for_card.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../chat/presentation/widgets/share_looking_for_sheet.dart';
import '../../controllers/looking_for_detail_controller.dart';
import '../../domain/looking_for_lifecycle.dart';
import '../widgets/create_looking_for_sheet.dart';
import '../widgets/report_looking_for_sheet.dart';

class LookingForDetailScreen extends StatelessWidget {
  const LookingForDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LookingForDetailController>();
    final post = controller.post;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Looking For'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: controller.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : post == null
          ? ErrorState(
              message:
                  controller.errorMessage ??
                  'This Looking For request is no longer available.',
              onRetry: controller.load,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                LookingForCard(
                  post: post,
                  layout: LookingForCardLayout.detail,
                  showShare: !controller.isSellerWorkspace && post.showInBrowse,
                  showRespondButton:
                      controller.isSellerWorkspace &&
                      !controller.isOwner &&
                      post.showInBrowse,
                  showOwnerActions:
                      controller.isOwner && !controller.isSellerWorkspace,
                  showReport: !controller.isOwner && post.showInBrowse,
                  onShare: () => _share(context, controller),
                  onRespond: () => _iHaveThis(context, controller),
                  onEdit: () => _edit(context, controller),
                  onDelete: () => _delete(context, controller),
                  onRepost: () => _repost(context, controller),
                  onReport: () => _report(context, controller),
                ),
              ],
            ),
    );
  }

  Future<void> _share(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
    final post = controller.post;
    if (post == null) return;
    final sent = await ShareLookingForSheet.show(
      context,
      post: post,
      controller: controller.looking,
    );
    if (!sent || !context.mounted) return;
    showThriftSnackBar(context, 'Request shared with selected sellers.');
  }

  Future<void> _iHaveThis(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
    final result = await controller.sendIHaveThis();
    if (!context.mounted) return;
    if (!result.isOk) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Message sent to the buyer.');
    if (result.conversationId != null) {
      context.push(RouteNames.chatThread(result.conversationId!));
    }
  }

  Future<void> _edit(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
    final post = controller.post;
    if (post == null) return;
    final saved = await CreateLookingForSheet.show(
      context,
      controller: controller.looking,
      existing: post,
    );
    if (!saved || !context.mounted) return;
    await controller.load();
    if (!context.mounted) return;
    showThriftSnackBar(context, 'Request updated.');
  }

  Future<void> _delete(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
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
    if (confirmed != true || !context.mounted) return;
    final error = await controller.delete();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Request removed from your list.');
    context.pop();
  }

  Future<void> _repost(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
    final post = controller.post;
    if (post == null || !post.canRepost) return;
    final saved = await CreateLookingForSheet.show(
      context,
      controller: controller.looking,
      existing: post,
      repost: true,
    );
    if (!saved || !context.mounted) return;
    await controller.load();
    if (!context.mounted) return;
    showThriftSnackBar(context, 'Request posted again.');
  }

  Future<void> _report(
    BuildContext context,
    LookingForDetailController controller,
  ) async {
    final post = controller.post;
    if (post == null) return;
    final choice = await ReportLookingForSheet.show(context);
    if (choice == null || !context.mounted) return;
    final error = await controller.looking.reportPost(
      postId: post.id,
      reason: choice.reason,
      details: choice.details,
    );
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Report sent. An admin will review it.');
  }
}
