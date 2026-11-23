import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final double? deltaPct;
  final bool invertDeltaColor; // e.g. for rejection rate, positive delta is bad

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.iconColor,
    this.deltaPct,
    this.invertDeltaColor = false,
  });

  @override
  Widget build(BuildContext context) {
    Color? chipColor;
    Color? chipTextColor;
    IconData? chipIcon;

    if (deltaPct != null) {
      final isPositive = deltaPct! >= 0;
      final isGood = invertDeltaColor ? !isPositive : isPositive;

      chipColor = isGood ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);
      chipTextColor = isGood ? AppColors.success : AppColors.danger;
      chipIcon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.slate,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: iconColor ?? AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (deltaPct != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(chipIcon, size: 12, color: chipTextColor),
                        const SizedBox(width: 2),
                        Text(
                          '${deltaPct! >= 0 ? '+' : '-'}${deltaPct!.abs().toStringAsFixed(1).replaceAll('.', ',')} %',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: chipTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'vs préc.',
                    style: TextStyle(fontSize: 11, color: AppColors.slate),
                  ),
                ] else if (subtitle != null) ...[
                  Text(
                    subtitle!,
                    style: const TextStyle(fontSize: 11, color: AppColors.slate),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
