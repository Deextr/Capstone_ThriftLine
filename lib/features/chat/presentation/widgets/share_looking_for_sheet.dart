import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/looking_for_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../buyer/controllers/looking_for_controller.dart';
import '../../data/conversation_service.dart';

class ShareLookingForSheet extends StatefulWidget {
  const ShareLookingForSheet({
    super.key,
    required this.post,
    required this.controller,
  });

  final LookingForModel post;
  final LookingForController controller;

  static Future<bool> show(
    BuildContext context, {
    required LookingForModel post,
    required LookingForController controller,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareLookingForSheet(post: post, controller: controller),
    );
    return sent == true;
  }

  @override
  State<ShareLookingForSheet> createState() => _ShareLookingForSheetState();
}

class _ShareLookingForSheetState extends State<ShareLookingForSheet> {
  final _selected = <String>{};
  List<FollowedSeller> _sellers = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = widget.controller.auth.user?.id;
    if (me == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in to share.';
      });
      return;
    }
    try {
      final sellers = await widget.controller.conversations.followedSellers(me);
      if (!mounted) return;
      setState(() {
        _sellers = sellers.where((s) => s.id != widget.post.buyerId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load sellers you follow.';
      });
    }
  }

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    setState(() => _sending = true);
    final error = await widget.controller.sharePost(
      post: widget.post,
      sellerIds: _selected.toList(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Share with sellers you follow',
                      style: AppTypography.heading.copyWith(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _sellers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Follow sellers first. Only shops you follow can receive this request.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _sellers.length,
                      itemBuilder: (_, i) {
                        final seller = _sellers[i];
                        final checked = _selected.contains(seller.id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: _sending
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(seller.id);
                                    } else {
                                      _selected.remove(seller.id);
                                    }
                                  });
                                },
                          secondary: ThriftAvatar(
                            imageUrl: seller.avatar,
                            size: 40,
                          ),
                          title: Text(seller.name),
                          subtitle: seller.shopName != null
                              ? Text(seller.shopName!)
                              : null,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ThriftButton(
                label: _sending ? 'Sending…' : 'Send',
                onPressed: _sending || _selected.isEmpty ? null : _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
