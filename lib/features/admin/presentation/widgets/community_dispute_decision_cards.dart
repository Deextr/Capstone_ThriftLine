import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/admin_report_decision_content.dart';

/// Equal-height, radio-style decision cards for the community dispute modal.
class CommunityDisputeDecisionCardGroup extends StatelessWidget {
  const CommunityDisputeDecisionCardGroup({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.stackBreakpoint = 560,
  });

  final List<CommunityDisputeDecisionOptionData> options;
  final String? selectedValue;
  final ValueChanged<String> onSelected;
  final double stackBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < stackBreakpoint;
        final cards = [
          for (final option in options)
            CommunityDisputeDecisionCard(
              option: option,
              isSelected: option.enabled && option.value == selectedValue,
              onSelect: () => onSelected(option.value),
            ),
        ];

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                cards[i],
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class CommunityDisputeDecisionCard extends StatefulWidget {
  const CommunityDisputeDecisionCard({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onSelect,
  });

  final CommunityDisputeDecisionOptionData option;
  final bool isSelected;
  final VoidCallback onSelect;

  static const int descriptionLines = 2;
  static const double borderWidth = 1.5;

  @override
  State<CommunityDisputeDecisionCard> createState() =>
      _CommunityDisputeDecisionCardState();
}

class _CommunityDisputeDecisionCardState
    extends State<CommunityDisputeDecisionCard> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.option.enabled;

  void _handleSelect() {
    if (!_enabled) return;
    widget.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _enabled && widget.isSelected;
    final borderColor = !_enabled
        ? AppColors.border.withValues(alpha: 0.75)
        : selected
        ? AppColors.primary
        : _focused
        ? AppColors.primary.withValues(alpha: 0.85)
        : _hovered
        ? AppColors.primary.withValues(alpha: 0.45)
        : AppColors.border;

    final background = !_enabled
        ? AppColors.background.withValues(alpha: 0.65)
        : selected
        ? AppColors.primary.withValues(alpha: 0.06)
        : _hovered || _focused
        ? AppColors.primary.withValues(alpha: 0.03)
        : AppColors.background;

    return Semantics(
      button: true,
      enabled: _enabled,
      selected: selected,
      label: '${widget.option.title}. ${widget.option.description}',
      child: FocusableActionDetector(
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _handleSelect();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _enabled ? _handleSelect : null,
              borderRadius: BorderRadius.circular(10),
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              highlightColor: AppColors.primary.withValues(alpha: 0.04),
              child: Ink(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: borderColor,
                    width: CommunityDisputeDecisionCard.borderWidth,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SelectionIndicator(
                            selected: selected,
                            enabled: _enabled,
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            widget.option.icon,
                            size: 18,
                            color: _iconColor(selected),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.option.title,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _titleColor(selected),
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height:
                            11 *
                            1.35 *
                            CommunityDisputeDecisionCard.descriptionLines,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            widget.option.description,
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              height: 1.35,
                              color: AppColors.textSecondary.withValues(
                                alpha: _enabled ? 1 : 0.7,
                              ),
                            ),
                            maxLines:
                                CommunityDisputeDecisionCard.descriptionLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _titleColor(bool selected) {
    if (!_enabled) {
      return AppColors.textSecondary.withValues(alpha: 0.75);
    }
    if (selected) return AppColors.primary;
    return AppColors.textPrimary;
  }

  Color _iconColor(bool selected) {
    if (!_enabled) {
      return AppColors.textSecondary.withValues(alpha: 0.55);
    }
    if (selected) return AppColors.primary;
    return AppColors.textSecondary;
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final outer = enabled
        ? (selected ? AppColors.primary : AppColors.border)
        : AppColors.border.withValues(alpha: 0.6);
    final inner = selected && enabled ? AppColors.primary : Colors.transparent;

    return SizedBox(
      width: 18,
      height: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: outer, width: 1.5),
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: selected && enabled ? 8 : 0,
            height: selected && enabled ? 8 : 0,
            decoration: BoxDecoration(color: inner, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
