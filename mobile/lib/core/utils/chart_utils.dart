import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'formatters.dart';

/// Standardized accessible chart tooltips and styling for MERCHANT PAY.
/// Ensures high-contrast readability (white text on dark slate-800 container),
/// prevents tooltip clipping on viewport boundaries, and formats monetary values in DZD.
class ChartUtils {
  static const Color tooltipBackground = Color(0xFF1E293B); // Slate-800: high contrast

  /// LineChart touch configuration with formatted currency and optional date/label.
  static LineTouchData lineTouchData({
    List<dynamic>? items,
    String Function(int index, double value)? formatter,
  }) {
    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => tooltipBackground,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipBorderRadius: BorderRadius.circular(6),
        getTooltipItems: (List<LineBarSpot> touchedSpots) {
          return touchedSpots.map((spot) {
            final idx = spot.spotIndex;
            String header = '';
            if (items != null && idx >= 0 && idx < items.length) {
              final it = items[idx];
              if (it is Map) {
                header = (it['label'] ?? it['period_label'] ?? it['date'] ?? '').toString();
              }
            }

            final String valStr = formatter != null
                ? formatter(idx, spot.y)
                : Formatters.formatDzd(spot.y);

            final displayText = header.isNotEmpty ? '$header\n$valStr' : valStr;

            return LineTooltipItem(
              displayText,
              const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                height: 1.3,
              ),
            );
          }).toList();
        },
      ),
    );
  }

  /// BarChart touch configuration with formatted values and labels.
  static BarTouchData barTouchData({
    List<dynamic>? items,
    String Function(int groupIndex, double value)? formatter,
  }) {
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => tooltipBackground,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipBorderRadius: BorderRadius.circular(6),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          String header = '';
          if (items != null && groupIndex >= 0 && groupIndex < items.length) {
            final it = items[groupIndex];
            if (it is Map) {
              header = (it['label'] ?? it['channel_display'] ?? it['category'] ?? '').toString();
            }
          }

          final String valStr = formatter != null
              ? formatter(groupIndex, rod.toY)
              : Formatters.formatDzd(rod.toY);

          final displayText = header.isNotEmpty ? '$header\n$valStr' : valStr;

          return BarTooltipItem(
            displayText,
            const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              height: 1.3,
            ),
          );
        },
      ),
    );
  }

  /// ScatterChart touch configuration with readable point descriptions.
  static ScatterTouchData scatterTouchData({
    List<dynamic>? items,
    String Function(int spotIndex, double amount, dynamic extra)? formatter,
  }) {
    return ScatterTouchData(
      enabled: true,
      touchTooltipData: ScatterTouchTooltipData(
        getTooltipColor: (_) => tooltipBackground,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipBorderRadius: BorderRadius.circular(6),
        getTooltipItems: (ScatterSpot spot) {
          final idx = spot.x.toInt();
          Map? it;
          if (items != null && idx >= 0 && idx < items.length && items[idx] is Map) {
            it = items[idx];
          }

          final status = it?['status'] ?? '';
          final amountStr = Formatters.formatDzd(spot.y);
          final text = status.isNotEmpty ? '$status\n$amountStr' : amountStr;

          return ScatterTooltipItem(
            text,
            textStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              height: 1.3,
            ),
          );
        },
      ),
    );
  }
}
