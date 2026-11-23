import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/kpi_card.dart';

class MerchantDashboardScreen extends ConsumerStatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  ConsumerState<MerchantDashboardScreen> createState() => _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends ConsumerState<MerchantDashboardScreen> {
  String _selectedPreset = '30d';
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
  }

  Future<void> _fetchDashboard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/merchant/dashboard/', queryParameters: {'preset': _selectedPreset});
      if (res.statusCode == 200) {
        setState(() {
          _data = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de charger les données du tableau de bord.";
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
      return AppErrorState(message: _error!, onRetry: _fetchDashboard);
    }

    if (_data == null) {
      return const AppEmptyState(
        title: "Aucune donnée disponible",
        message: "Vos indicateurs apparaîtront dès vos premières transactions.",
      );
    }

    final kpis = _data!['kpis'] ?? {};
    final comp = _data!['comparison'] ?? {};
    final trends = (_data!['trends'] as List?) ?? [];
    final prevTrends = (_data!['prev_trends'] as List?) ?? [];
    final channels = (_data!['channel_distribution']?['channels'] as List?) ?? [];
    final peakPeriods = _data!['peak_periods'] ?? {};
    final monthlyGoal = _data!['monthly_goal'];
    final latestAlerts = (_data!['latest_alerts'] as List?) ?? [];
    final latestTxs = (_data!['latest_transactions'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _fetchDashboard,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header & Period Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tableau de bord',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      'Synthèse de vos encaissements et indicateurs clés',
                      style: TextStyle(fontSize: 13, color: AppColors.slate),
                    ),
                  ],
                ),
                PeriodSelectorWidget(
                  currentPreset: _selectedPreset,
                  onPresetChanged: (val) {
                    setState(() => _selectedPreset = val);
                    _fetchDashboard();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // KPI Grid (Responsive 1 to 2 to 4 columns)
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 550 ? 2 : 1);
                return GridView.count(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    KpiCard(
                      title: "Chiffre d'affaires net",
                      value: Formatters.formatDzd(kpis['net_revenue']),
                      icon: Icons.account_balance_wallet,
                      iconColor: AppColors.primary,
                      deltaPct: comp['net_revenue']?['delta_pct']?.toDouble(),
                    ),
                    KpiCard(
                      title: "Transactions acceptées",
                      value: '${kpis['accepted_count'] ?? 0}',
                      icon: Icons.check_circle_outline,
                      iconColor: AppColors.success,
                      deltaPct: comp['accepted_count']?['delta_pct']?.toDouble(),
                    ),
                    KpiCard(
                      title: "Taux de réussite",
                      value: Formatters.formatPct(kpis['success_rate']),
                      icon: Icons.verified_outlined,
                      iconColor: AppColors.info,
                      deltaPct: comp['success_rate']?['delta_pct']?.toDouble(),
                    ),
                    KpiCard(
                      title: "Panier moyen",
                      value: Formatters.formatDzd(kpis['avg_ticket']),
                      icon: Icons.shopping_basket_outlined,
                      iconColor: AppColors.warning,
                      deltaPct: comp['avg_ticket']?['delta_pct']?.toDouble(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Charts Row: Revenue Trend & Channels Donut
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildRevenueTrendCard(trends, prevTrends)),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildChannelDonutCard(channels)),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      _buildRevenueTrendCard(trends, prevTrends),
                      const SizedBox(height: 16),
                      _buildChannelDonutCard(channels),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Second Row: Monthly Goal & Peak Hours & Latest Alerts
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (monthlyGoal != null) ...[
                        Expanded(child: _buildGoalCard(monthlyGoal)),
                        const SizedBox(width: 16),
                      ],
                      Expanded(child: _buildPeakHoursCard(peakPeriods)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildLatestAlertsCard(latestAlerts)),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      if (monthlyGoal != null) ...[
                        _buildGoalCard(monthlyGoal),
                        const SizedBox(height: 16),
                      ],
                      _buildPeakHoursCard(peakPeriods),
                      const SizedBox(height: 16),
                      _buildLatestAlertsCard(latestAlerts),
                    ],
                  );
                }
              },
            ),
            const SizedBox(height: 20),

            // Latest Transactions Table
            _buildLatestTransactionsCard(latestTxs),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueTrendCard(List trends, List prevTrends) {
    List<FlSpot> currSpots = [];
    List<FlSpot> prevSpots = [];

    for (int i = 0; i < trends.length; i++) {
      final rev = double.tryParse(trends[i]['revenue']?.toString() ?? '0') ?? 0.0;
      currSpots.add(FlSpot(i.toDouble(), rev));
    }

    for (int i = 0; i < prevTrends.length && i < trends.length; i++) {
      final prevRev = double.tryParse(prevTrends[i]['revenue']?.toString() ?? '0') ?? 0.0;
      prevSpots.add(FlSpot(i.toDouble(), prevRev));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Évolution du Chiffre d'Affaires", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text("Comparaison avec la période précédente", style: TextStyle(fontSize: 12, color: AppColors.slate)),
                  ],
                ),
                Row(
                  children: [
                    _legendItem(AppColors.primary, "Période actuelle"),
                    const SizedBox(width: 12),
                    _legendItem(AppColors.comparison, "Période précédente"),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: currSpots.isEmpty
                  ? const Center(child: Text("Données insuffisantes"))
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
                        ),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (val, _) {
                                if (val == 0) return const SizedBox.shrink();
                                return Text(
                                  val >= 1000 ? '${(val / 1000).toStringAsFixed(0)}k' : '${val.toInt()}',
                                  style: const TextStyle(fontSize: 10, color: AppColors.slate),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: (trends.length / 5).ceil().toDouble(),
                              getTitlesWidget: (val, _) {
                                int idx = val.toInt();
                                if (idx >= 0 && idx < trends.length) {
                                  return Text(trends[idx]['label'] ?? '', style: const TextStyle(fontSize: 10, color: AppColors.slate));
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          if (prevSpots.isNotEmpty)
                            LineChartBarData(
                              spots: prevSpots,
                              isCurved: true,
                              color: AppColors.comparison.withOpacity(0.6),
                              barWidth: 2,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              dashArray: [5, 5],
                            ),
                          LineChartBarData(
                            spots: currSpots,
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primary.withOpacity(0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelDonutCard(List channels) {
    double cibPct = 65.0;
    double edaPct = 35.0;
    for (var ch in channels) {
      if (ch['channel'] == 'CIB') cibPct = (ch['amount_pct'] as num?)?.toDouble() ?? 65.0;
      if (ch['channel'] == 'EDAHABIA') edaPct = (ch['amount_pct'] as num?)?.toDouble() ?? 35.0;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Répartition par Carte", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Text("Part du volume accepté", style: TextStyle(fontSize: 12, color: AppColors.slate)),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(
                      value: cibPct,
                      title: '${cibPct.toStringAsFixed(0)} %',
                      color: AppColors.cib,
                      radius: 35,
                      titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    PieChartSectionData(
                      value: edaPct,
                      title: '${edaPct.toStringAsFixed(0)} %',
                      color: AppColors.edahabia,
                      radius: 35,
                      titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _legendItem(AppColors.cib, "Carte CIB (${cibPct.toStringAsFixed(1)} %)"),
                _legendItem(AppColors.edahabia, "EDAHABIA (${edaPct.toStringAsFixed(1)} %)"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(Map<String, dynamic> goal) {
    final pct = (goal['percent'] as num?)?.toDouble() ?? 0.0;
    final isReached = goal['is_reached'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Objectif Mensuel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Icon(
                  isReached ? Icons.check_circle : Icons.flag_outlined,
                  color: isReached ? AppColors.success : AppColors.primary,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(isReached ? AppColors.success : AppColors.primary),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Formatters.formatDzd(goal['achieved']),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '${pct.toStringAsFixed(1)} %',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isReached ? AppColors.success : AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Objectif : ${Formatters.formatDzd(goal['goal'])}",
              style: const TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeakHoursCard(Map<String, dynamic> peaks) {
    final topHours = (peaks['top_hours'] as List?) ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Heures de Pointe", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Icon(Icons.access_time, color: AppColors.slate, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            if (topHours.isEmpty)
              const Text("Données en cours de consolidation...", style: TextStyle(fontSize: 12, color: AppColors.slate))
            else
              ...topHours.map((h) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(h['label'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      Text('${h['count']} tx', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestAlertsCard(List alerts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Dernières Alertes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                TextButton(
                  onPressed: () => context.go('/m/alerts'),
                  child: const Text("Voir tout", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (alerts.isEmpty)
              const Text("Aucune alerte récente", style: TextStyle(fontSize: 12, color: AppColors.slate))
            else
              ...alerts.take(2).map((a) {
                Color sevColor = AppColors.info;
                if (a['severity'] == 'CRITICAL') sevColor = AppColors.danger;
                if (a['severity'] == 'WARNING') sevColor = AppColors.warning;
                if (a['severity'] == 'SUCCESS') sevColor = AppColors.success;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: sevColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sevColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    a['title'] ?? '',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sevColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestTransactionsCard(List txs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Dernières Transactions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                TextButton(
                  onPressed: () => context.go('/m/transactions'),
                  child: const Text("Explorer les transactions"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.background),
                columns: const [
                  DataColumn(label: Text('Référence', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Montant', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Canal', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Statut', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: txs.map((tx) {
                  return DataRow(cells: [
                    DataCell(Text(tx['reference'] ?? '')),
                    DataCell(Text(Formatters.formatDateTime(tx['transaction_date']))),
                    DataCell(Text(Formatters.formatDzd(tx['amount']), style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(tx['payment_channel'] ?? '')),
                    DataCell(_buildStatusBadge(tx['transaction_status'])),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color bg = AppColors.background;
    Color fg = AppColors.slate;
    String label = status ?? '';

    switch (status) {
      case 'ACCEPTED':
        bg = const Color(0xFFE8F5E9);
        fg = AppColors.success;
        label = 'Acceptée';
        break;
      case 'REJECTED':
        bg = const Color(0xFFFFEBEE);
        fg = AppColors.danger;
        label = 'Rejetée';
        break;
      case 'CANCELLED':
        bg = const Color(0xFFFFF3E0);
        fg = AppColors.warning;
        label = 'Annulée';
        break;
      case 'REFUNDED':
        bg = const Color(0xFFE1F5FE);
        fg = AppColors.info;
        label = 'Remboursée';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
      ],
    );
  }
}
