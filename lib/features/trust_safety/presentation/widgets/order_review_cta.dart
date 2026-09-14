import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';
import '../../../../models/order_model.dart';
import '../../../../models/review_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/review_rules.dart';

class OrderReviewCta extends StatelessWidget {
  const OrderReviewCta({
    super.key,
    required this.order,
    required this.existing,
    required this.ratingBuyer,
    this.onReturned,
  });

  final OrderModel order;
  final ReviewModel? existing;
  final bool ratingBuyer;
  final VoidCallback? onReturned;

  @override
  Widget build(BuildContext context) {
    if (!order.isCompleted) return const SizedBox.shrink();

    final kind = reviewActionKind(existing);
    return ThriftButton(
      label: reviewActionLabel(kind, ratingBuyer: ratingBuyer),
      variant: kind == ReviewActionKind.leave
          ? ThriftButtonVariant.primary
          : ThriftButtonVariant.outline,
      onPressed: () async {
        await context.push(RouteNames.leaveReviewFor(order.id));
        onReturned?.call();
      },
    );
  }
}
