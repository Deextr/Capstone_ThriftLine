import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';

/// Original ThriftLine earnings card: balance on top, shop stats along the bottom.
///
/// This is a balance card, not a payment card.
class SellerAvailableEarningsCard extends StatelessWidget {
  const SellerAvailableEarningsCard({
    super.key,
    this.amountLabel,
    this.statusLine,
    this.listingsLabel = '–',
    this.pendingLabel = '–',
    this.ratingLabel = '–',
    this.isLoading = false,
    this.errorMessage,
    this.showPayout = false,
    this.isRequesting = false,
    this.onRequestPayout,
    this.onRetry,
    this.onListings,
    this.onPending,
  });

  final String? amountLabel;
  final String? statusLine;
  final String listingsLabel;
  final String pendingLabel;
  final String ratingLabel;
  final bool isLoading;
  final String? errorMessage;
  final bool showPayout;
  final bool isRequesting;
  final VoidCallback? onRequestPayout;
  final VoidCallback? onRetry;
  final VoidCallback? onListings;
  final VoidCallback? onPending;

  @override
  Widget build(BuildContext context) {
    final failed = errorMessage != null && !isLoading;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusXl),
        child: Stack(
          children: [
            const Positioned.fill(child: _CardCircles()),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: failed
                  ? _ErrorBody(onRetry: onRetry)
                  : isLoading
                  ? const _LoadingBody()
                  : _LoadedBody(
                      amountLabel: amountLabel ?? '',
                      statusLine: statusLine ?? '',
                      listingsLabel: listingsLabel,
                      pendingLabel: pendingLabel,
                      ratingLabel: ratingLabel,
                      showPayout: showPayout,
                      isRequesting: isRequesting,
                      onRequestPayout: onRequestPayout,
                      onListings: onListings,
                      onPending: onPending,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardCircles extends StatelessWidget {
  const _CardCircles();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -28,
            child: _Circle(diameter: 130, alpha: 0.06),
          ),
          Positioned(
            bottom: -18,
            right: 60,
            child: _Circle(diameter: 80, alpha: 0.05),
          ),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.diameter, required this.alpha});

  final double diameter;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.amountLabel,
    required this.statusLine,
    required this.listingsLabel,
    required this.pendingLabel,
    required this.ratingLabel,
    required this.showPayout,
    required this.isRequesting,
    this.onRequestPayout,
    this.onListings,
    this.onPending,
  });

  final String amountLabel;
  final String statusLine;
  final String listingsLabel;
  final String pendingLabel;
  final String ratingLabel;
  final bool showPayout;
  final bool isRequesting;
  final VoidCallback? onRequestPayout;
  final VoidCallback? onListings;
  final VoidCallback? onPending;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available earnings',
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: 'Available earnings $amountLabel. $statusLine',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amountLabel,
              maxLines: 1,
              style: AppTypography.display.copyWith(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (statusLine.isNotEmpty) _StatusPill(label: statusLine),
            if (showPayout)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  backgroundColor: Colors.white,
                  minimumSize: const Size(44, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: isRequesting ? null : onRequestPayout,
                child: Text(
                  isRequesting ? 'Requesting…' : 'Request payout',
                  style: AppTypography.label.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 14),
        Row(
          children: [
            _MiniStat(
              label: 'Listings',
              value: listingsLabel,
              icon: Icons.storefront_outlined,
              onTap: onListings,
            ),
            const _VertDivider(),
            _MiniStat(
              label: 'Pending',
              value: pendingLabel,
              icon: Icons.hourglass_top_rounded,
              onTap: onPending,
            ),
            const _VertDivider(),
            _MiniStat(
              label: 'Rating',
              value: ratingLabel,
              icon: Icons.star_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.80), size: 18),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.subheading.copyWith(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 11,
          ),
        ),
      ],
    );
    return Expanded(
      child: Semantics(
        button: onTap != null,
        label: '$label $value',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: column,
            ),
          ),
        ),
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  const _VertDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      color: Colors.white.withValues(alpha: 0.18),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available earnings',
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        const _Bone(width: 168, height: 28),
        const SizedBox(height: 10),
        const _Bone(width: 120, height: 22, radius: 20),
        const SizedBox(height: 18),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 14),
        const Row(
          children: [
            _MiniStat(
              label: 'Listings',
              value: '–',
              icon: Icons.storefront_outlined,
            ),
            _VertDivider(),
            _MiniStat(
              label: 'Pending',
              value: '–',
              icon: Icons.hourglass_top_rounded,
            ),
            _VertDivider(),
            _MiniStat(label: 'Rating', value: '–', icon: Icons.star_rounded),
          ],
        ),
      ],
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height, this.radius = 6});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available earnings',
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Unable to load balance',
          style: AppTypography.body.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 40),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
