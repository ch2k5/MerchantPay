import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/chart_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantCollectionsScreen extends ConsumerStatefulWidget {
  const MerchantCollectionsScreen({super.key});

  @override
  ConsumerState<MerchantCollectionsScreen> createState() => _MerchantCollectionsScreenState();
}

class _MerchantCollectionsScreenState extends ConsumerState<MerchantCollectionsScreen> {
  String _selectedPreset = 'all';
  String _granularity = 'day';
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchCollections();
  }

  Future<void> _fetchCollections() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/merchant/collections/', queryParameters: {
        'preset': _selectedPreset,
        'granularity': _granularity,
      });
      if (res.statusCode == 200) {
        setState(() {
          _data = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Erreur lors du chargement des encaissements.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return AppErrorState(message: _error!, onRetry: _fetchCollections);

    final totals = _data?['totals'] ?? {};
    final breakdown = (_data?['breakdown'] as List?) ?? [];
    final comparison = _data?['comparison']?['deltas'] ?? {};
    final summaryText = _data?['summary'] ?? '';

    final double maxRevenue = breakdown.fold(100.0, (m, t) {
      final val = double.tryParse((t['revenue'] ?? t['net_revenue'] ?? t['volume'] ?? 0).toString()) ?? 0.0;
      return max(m, val);
    });

    double totalBreakdownRevenue = 0;
    int totalBreakdownTx = 0;
    int totalAcceptedTx = 0;
    double peakRevenue = 0;
    String peakPeriod = '';

    for (var r in breakdown) {
      final rev = double.tryParse((r['revenue'] ?? r['net_revenue'] ?? 0).toString()) ?? 0.0;
      final tot = int.tryParse(r['total_count']?.toString() ?? '0') ?? 0;
      final acc = int.tryParse(r['accepted_count']?.toString() ?? '0') ?? 0;
      totalBreakdownRevenue += rev;
      totalBreakdownTx += tot;
      totalAcceptedTx += acc;
      if (rev > peakRevenue) {
        peakRevenue = rev;
        peakPeriod = (r['label'] ?? r['date'] ?? '').toString();
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Preset
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Suivi des Encaissements", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("Module 3 — Audit des flux acceptés, rejetés et remboursés", style: TextStyle(fontSize: 13, color: AppColors.slate)),
                ],
              ),
              PeriodSelectorWidget(
                currentPreset: _selectedPreset,
                onPresetChanged: (val) {
                  setState(() => _selectedPreset = val);
                  _fetchCollections();
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Textual Summary Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    summaryText,
                    style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Status Cards Breakdown
          Row(
            children: [
              Expanded(
                child: _statusBox(
                  "Acceptées",
                  Formatters.formatDzd(totals['accepted_amount']),
                  "${totals['accepted_count'] ?? 0} transactions",
                  AppColors.success,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusBox(
                  "Rejetées",
                  Formatters.formatDzd(totals['rejected_amount']),
                  "${totals['rejected_count'] ?? 0} transactions",
                  AppColors.danger,
                  Icons.highlight_off,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusBox(
                  "Annulées",
                  Formatters.formatDzd(totals['cancelled_amount']),
                  "${totals['cancelled_count'] ?? 0} transactions",
                  AppColors.warning,
                  Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statusBox(
                  "Remboursées",
                  Formatters.formatDzd(totals['refunded_amount']),
                  "${totals['refunded_count'] ?? 0} transactions",
                  AppColors.info,
                  Icons.replay,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Two-Period Comparison Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Comparaison avec la période précédente", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  Table(
                    border: TableBorder.all(color: AppColors.border, width: 0.5),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: AppColors.background),
                        children: const [
                          Padding(padding: EdgeInsets.all(8.0), child: Text("Indicateur", style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8.0), child: Text("Période actuelle", style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8.0), child: Text("Période précédente", style: TextStyle(fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8.0), child: Text("Variation", style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                      _cmpRow("Volume total (tx)", comparison['total_transactions']),
                      _cmpRow("Transactions acceptées", comparison['accepted_count']),
                      _cmpRow("Revenu net", comparison['net_revenue'], isMoney: true),
                      _cmpRow("Taux de succès", comparison['success_rate'], isPct: true),
                      _cmpRow("Taux de rejet", comparison['rejection_rate'], isPct: true),
                      _cmpRow("Panier moyen", comparison['avg_ticket'], isMoney: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Period Breakdown: Temporal Chart + Detailed Audit Table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Ventilation chronologique", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            "Rythme temporel des encaissements par ${_granularity == 'month' ? 'mois' : _granularity == 'week' ? 'semaine' : 'jour'}",
                            style: const TextStyle(fontSize: 12, color: AppColors.slate),
                          ),
                        ],
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'day', label: Text('Jour')),
                          ButtonSegment(value: 'week', label: Text('Semaine')),
                          ButtonSegment(value: 'month', label: Text('Mois')),
                        ],
                        selected: {_granularity},
                        onSelectionChanged: (set) {
                          setState(() => _granularity = set.first);
                          _fetchCollections();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Visual Guide Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.show_chart, color: AppColors.primary, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Ce graphique de ventilation chronologique illustre l'évolution temporelle de vos encaissements nets en dinars algériens (DZD). Survolez un point pour consulter le détail de la période ainsi que la répartition entre transactions acceptées et rejetées.",
                            style: TextStyle(fontSize: 12, color: AppColors.slate, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dynamic summary KPI chips
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _kpiChip("Encaissement consolidé", Formatters.formatDzd(totalBreakdownRevenue), AppColors.primary),
                      _kpiChip("Transactions traitées", "$totalBreakdownTx ($totalAcceptedTx acceptées)", AppColors.success),
                      if (peakPeriod.isNotEmpty)
                        _kpiChip("Pic de la période", "$peakPeriod (${Formatters.formatDzd(peakRevenue)})", AppColors.warning),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Temporal Line Chart
                  if (breakdown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.0),
                      child: Center(child: Text("Aucune donnée temporelle disponible sur la période.")),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: LineChart(
                        LineChartData(
                          lineTouchData: ChartUtils.lineTouchData(
                            items: breakdown,
                            formatter: (idx, val) {
                              if (idx >= 0 && idx < breakdown.length) {
                                final item = breakdown[idx];
                                final acc = item['accepted_count'] ?? 0;
                                final rej = item['rejected_count'] ?? 0;
                                return "${Formatters.formatDzd(val)}\n$acc acceptée(s) · $rej rejetée(s)";
                              }
                              return Formatters.formatDzd(val);
                            },
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.8),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 55,
                                getTitlesWidget: (val, _) => Text(
                                  "${(val / 1000).toInt()}k",
                                  style: const TextStyle(fontSize: 10, color: AppColors.slate),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: max(1.0, (breakdown.length / 6).floorToDouble()),
                                getTitlesWidget: (idx, _) {
                                  int i = idx.toInt();
                                  if (i >= 0 && i < breakdown.length) {
                                    final label = breakdown[i]['label'] ?? breakdown[i]['period_label'] ?? breakdown[i]['date'] ?? '';
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(label.toString().split(' ').first, style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          minY: 0,
                          maxY: maxRevenue > 0 ? maxRevenue * 1.15 : 100.0,
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (int i = 0; i < breakdown.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    (double.tryParse((breakdown[i]['revenue'] ?? breakdown[i]['net_revenue'] ?? 0).toString()) ?? 0.0),
                                  ),
                              ],
                              isCurved: true,
                              color: AppColors.primary,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: FlDotData(
                                show: breakdown.length <= 15,
                                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                                  radius: 3,
                                  color: AppColors.primary,
                                  strokeWidth: 1.5,
                                  strokeColor: Colors.white,
                                ),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                color: AppColors.primary.withValues(alpha: 0.12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),

                  // Data Table section title
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Relevé détaillé de la ventilation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text("Données certifiées SATIM", style: TextStyle(fontSize: 11, color: AppColors.slate)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Scrollable Table container
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 350),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AppColors.background),
                          columns: const [
                            DataColumn(label: Text('Date / Période', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Transactions totales', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Acceptées', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Rejetées', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Chiffre d'affaires", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: breakdown.map((row) {
                            return DataRow(cells: [
                              DataCell(Text((row['label'] ?? row['date'] ?? '').toString())),
                              DataCell(Text('${row['total_count'] ?? 0}')),
                              DataCell(Text('${row['accepted_count'] ?? 0}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))),
                              DataCell(Text('${row['rejected_count'] ?? 0}', style: const TextStyle(color: AppColors.danger))),
                              DataCell(Text(Formatters.formatDzd(row['revenue'] ?? row['net_revenue']), style: const TextStyle(fontWeight: FontWeight.bold))),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _cmpRow(String label, Map? item, {bool isMoney = false, bool isPct = false}) {
    final curr = item?['current'];
    final prev = item?['previous'];
    final deltaPct = item?['delta_pct'];

    String fmt(dynamic val) {
      if (val == null) return '-';
      if (isMoney) return Formatters.formatDzd(val);
      if (isPct) return Formatters.formatPct(val);
      return val.toString();
    }

    String varStr = deltaPct != null ? '${deltaPct > 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)} %' : '-';
    Color varColor = deltaPct != null
        ? (deltaPct >= 0 ? AppColors.success : AppColors.danger)
        : AppColors.slate;

    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(8.0), child: Text(label, style: const TextStyle(fontSize: 13))),
        Padding(padding: const EdgeInsets.all(8.0), child: Text(fmt(curr), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Padding(padding: const EdgeInsets.all(8.0), child: Text(fmt(prev), style: const TextStyle(fontSize: 13, color: AppColors.slate))),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(varStr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: varColor)),
        ),
      ],
    );
  }

  Widget _statusBox(String title, String amount, String count, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate)),
                Icon(icon, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Text(amount, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(count, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
          ],
        ),
      ),
    );
  }

  static Widget _kpiChip(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text("$title: ", style: const TextStyle(fontSize: 12, color: AppColors.slate)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
