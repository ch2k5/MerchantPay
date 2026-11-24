import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantAnalyticsScreen extends ConsumerStatefulWidget {
  const MerchantAnalyticsScreen({super.key});

  @override
  ConsumerState<MerchantAnalyticsScreen> createState() => _MerchantAnalyticsScreenState();
}

class _MerchantAnalyticsScreenState extends ConsumerState<MerchantAnalyticsScreen> {
  String _selectedPreset = '30d';
  String _granularity = 'daily';
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get(
        '/merchant/analytics/',
        queryParameters: {
          'preset': _selectedPreset,
          'granularity': _granularity,
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          _data = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de charger les analyses avancées.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _fetchAnalytics);
    }

    if (_data == null) {
      return const AppEmptyState(
        title: "Données indisponibles",
        message: "Aucune donnée d'analyse disponible pour la période.",
      );
    }

    final trends = (_data!['trends'] as List?) ?? [];
    final channelDist = _data!['channel_distribution'] ?? {};
    final channels = (channelDist['channels'] as List?) ?? [];
    final heatmap = _data!['heatmap'] ?? {};
    final matrix = (heatmap['matrix'] as List?) ?? [];
    final peakSlots = (heatmap['peak_slots'] as List?) ?? [];
    final lowSlots = (heatmap['low_slots'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _fetchAnalytics,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analyses Détaillées',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      'Évolution temporelle, répartition par carte et carte de chaleur horaire',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
                PeriodSelectorWidget(
                  currentPreset: _selectedPreset,
                  onPresetChanged: (p) {
                    setState(() {
                      _selectedPreset = p;
                    });
                    _fetchAnalytics();
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Trend Chart Section with Granularity Selector
            _buildTrendsCard(trends),
            const SizedBox(height: 24),

            // 2-column: Channels & Heatmap highlights
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                return isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildChannelCard(channels, channelDist)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildHeatmapHighlights(peakSlots, lowSlots)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildChannelCard(channels, channelDist),
                          const SizedBox(height: 20),
                          _buildHeatmapHighlights(peakSlots, lowSlots),
                        ],
                      );
              },
            ),
            const SizedBox(height: 24),

            // 7x24 Heatmap Grid
            _buildHeatmapGrid(matrix),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsCard(List trends) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tendance des Encaissements',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  Text('Volume du chiffre d\'affaires sur la période', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'daily', label: Text('Jour')),
                  ButtonSegment(value: 'weekly', label: Text('Semaine')),
                  ButtonSegment(value: 'monthly', label: Text('Mois')),
                ],
                selected: {_granularity},
                onSelectionChanged: (set) {
                  setState(() {
                    _granularity = set.first;
                  });
                  _fetchAnalytics();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 260,
            child: trends.isEmpty
                ? const Center(child: Text("Données insuffisantes pour la courbe"))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (val) => const FlLine(color: AppColors.border, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: (trends.length / 6).clamp(1.0, 10.0),
                            getTitlesWidget: (val, meta) {
                              final idx = val.toInt();
                              if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                              final label = trends[idx]['period_label']?.toString() ?? '';
                              final shortLabel = label.length > 5 ? label.substring(5) : label;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(shortLabel, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 55,
                            getTitlesWidget: (val, meta) {
                              if (val == meta.max || val == meta.min) return const SizedBox.shrink();
                              final kVal = (val / 1000).toStringAsFixed(0);
                              return Text('${kVal}k', style: const TextStyle(fontSize: 10, color: AppColors.muted));
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: List.generate(trends.length, (i) {
                            final rev = (trends[i]['revenue'] as num?)?.toDouble() ?? 0.0;
                            return FlSpot(i.toDouble(), rev);
                          }),
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withValues(alpha: 0.1),
                          ),
                          dotData: FlDotData(show: trends.length <= 15),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(List channels, Map channelDist) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Répartition par Type de Carte',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          const Text('Part des transactions CIB vs EDAHABIA', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 20),
          Row(
            children: [
              SizedBox(
                height: 140,
                width: 140,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 36,
                    sections: channels.map((c) {
                      final isCib = c['channel'] == 'CIB';
                      final share = (c['share_pct'] as num?)?.toDouble() ?? (c['amount_pct'] as num?)?.toDouble() ?? 0.0;
                      return PieChartSectionData(
                        value: share <= 0 ? 0.1 : share,
                        title: share <= 0 ? '' : '${share.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        color: isCib ? AppColors.cibBlue : AppColors.edahabiaGold,
                        radius: 36,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: channels.map((c) {
                    final isCib = c['channel'] == 'CIB';
                    final color = isCib ? AppColors.cibBlue : AppColors.edahabiaGold;
                    final rev = (c['revenue'] as num?)?.toDouble() ?? (c['accepted_amount'] as num?)?.toDouble() ?? 0.0;
                    final cnt = c['count'] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Row(
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c['channel_display'] ?? c['channel'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('$cnt transactions', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                              ],
                            ),
                          ),
                          Text(formatDzd(rev), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapHighlights(List peakSlots, List lowSlots) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Créneaux Clés de Fréquentation',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          const Text('Heures de forte et faible affluence client', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          // Peaks
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.trending_up, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Heures d\'affluence maximale (Pointe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success)),
                      const SizedBox(height: 4),
                      Text(
                        peakSlots.isEmpty
                            ? 'Activité répartie uniformément'
                            : peakSlots.map((p) => '${p['day_name']} à ${p['hour']}h (${p['count']} tx)').join(' • '),
                        style: const TextStyle(fontSize: 12, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Lows
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.nightlight_round, color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Heures creuses récurrentes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.warning)),
                      const SizedBox(height: 4),
                      Text(
                        lowSlots.isEmpty
                            ? 'Pas de creux critique identifié'
                            : lowSlots.take(3).map((l) => '${l['day_name']} à ${l['hour']}h').join(' • '),
                        style: const TextStyle(fontSize: 12, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid(List matrix) {
    final days = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
    // Find max count for color scale
    int maxCount = 1;
    for (var cell in matrix) {
      if (cell is Map) {
        final c = (cell['count'] as num?)?.toInt() ?? 0;
        if (c > maxCount) maxCount = c;
      } else if (cell is List) {
        for (var sub in cell) {
          final c = (sub as num?)?.toInt() ?? 0;
          if (c > maxCount) maxCount = c;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Matrice d\'Activité 7j / 24h', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Intensité des transactions par jour de semaine et heure', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
              Row(
                children: [
                  const Text('Moins', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  const SizedBox(width: 6),
                  Container(width: 12, height: 12, color: const Color(0xFFF1F5F9)),
                  const SizedBox(width: 3),
                  Container(width: 12, height: 12, color: AppColors.primary.withValues(alpha: 0.3)),
                  const SizedBox(width: 3),
                  Container(width: 12, height: 12, color: AppColors.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 3),
                  Container(width: 12, height: 12, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text('Plus', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 780,
              child: Column(
                children: [
                  // Hour headers (0..23)
                  Row(
                    children: [
                      const SizedBox(width: 90),
                      ...List.generate(24, (h) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              h % 3 == 0 ? '${h}h' : '',
                              style: const TextStyle(fontSize: 10, color: AppColors.muted),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Day rows
                  ...List.generate(7, (d) {
                    final dayName = days[d];
                    final dayCells = matrix.where((m) => m is Map && m['day_index'] == d).toList();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              dayName,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.ink),
                            ),
                          ),
                          ...List.generate(24, (h) {
                            final cell = dayCells.firstWhere(
                              (c) => c['hour'] == h,
                              orElse: () => {'count': 0, 'revenue': 0},
                            );
                            final count = (cell['count'] as num?)?.toInt() ?? 0;
                            final rev = (cell['revenue'] as num?)?.toDouble() ?? 0.0;
                            final intensity = maxCount > 0 ? (count / maxCount) : 0.0;
                            Color bg;
                            if (count == 0) {
                              bg = const Color(0xFFF1F5F9);
                            } else if (intensity < 0.3) {
                              bg = AppColors.primary.withValues(alpha: 0.25);
                            } else if (intensity < 0.7) {
                              bg = AppColors.primary.withValues(alpha: 0.55);
                            } else {
                              bg = AppColors.primary;
                            }

                            return Expanded(
                              child: Tooltip(
                                message: '$dayName à ${h}h : $count tx (${formatDzd(rev)})',
                                child: Container(
                                  height: 22,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
