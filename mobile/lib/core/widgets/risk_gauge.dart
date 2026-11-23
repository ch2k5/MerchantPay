import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class RiskGauge extends StatelessWidget {
  final int score;
  final String? level;
  final double size;

  const RiskGauge({
    super.key,
    required this.score,
    this.level,
    this.size = 140,
  });

  Color get scoreColor {
    if (score >= 70) return AppColors.danger;
    if (score >= 40) return AppColors.warning;
    return AppColors.success;
  }

  String get effectiveLevel {
    if (level != null && level!.isNotEmpty) return level!.toUpperCase();
    if (score >= 70) return 'HIGH';
    if (score >= 40) return 'MEDIUM';
    return 'LOW';
  }

  String get levelLabel {
    switch (effectiveLevel) {
      case 'HIGH':
        return 'Élevé';
      case 'MEDIUM':
        return 'Modéré';
      default:
        return 'Faible';
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (score.clamp(0, 100)) / 100.0;
    final strokeWidth = size * 0.085;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: strokeWidth,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  '/100',
                  style: TextStyle(
                    fontSize: size * 0.1,
                    color: AppColors.slate,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (size >= 80) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scoreColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              levelLabel,
              style: TextStyle(
                color: scoreColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
