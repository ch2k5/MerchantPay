import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/kpi_card.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
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
      final res = await client.get('/admin/dashboard/', queryParameters: {'preset': _selectedPreset});
      if (res.statusCode == 200) {
        setState(() {
          _data = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de charger la supervision SATIM.";
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
        title: "Données indisponibles",
        message: "Aucune donnée de supervision globale disponible.",
      );
    }

    final kpis = _data!['kpis'] ?? {};
    final comp = _data!['comparison'] ?? {};
    final riskDist = _data!['risk_distribution'] ?? {};
    final topRev = (_data!['top_merchants_by_revenue'] as List?) ?? [];
    final topRej = (_data!['top_merchants_by_rejections'] as List?) ?? [];
    final summaryTables = _data!['summary_tables'] as Map?;

    return RefreshIndicator(
      onRefresh: _fetchDashboard,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supervision Globale SATIM',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      'Monitoring du réseau commerçants CIB et EDAHABIA en temps réel',
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
                    _fetchDashboard();
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Top KPI Row
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                final items = [
                  KpiCard(
                    title: 'Volume Global',
                    value: formatDzd(kpis['total_volume'] ?? 0),
                    deltaPct: (comp['volume_delta_pct'] as num?)?.toDouble(),
                    subtitle: 'Flux financier traité',
                    icon: Icons.account_balance,
                    iconColor: AppColors.primary,
                  ),
                  KpiCard(
                    title: 'Transactions Traitées',
                    value: '${kpis['transaction_count'] ?? 0}',
                    deltaPct: (comp['count_delta_pct'] as num?)?.toDouble(),
                    subtitle: 'Opérations réseau',
                    icon: Icons.receipt_long,
                    iconColor: AppColors.cibBlue,
                  ),
                  KpiCard(
                    title: 'Taux de Succès Global',
                    value: formatPct(kpis['success_rate'] ?? 0),
                    subtitle: 'Performance des autorisations',
                    icon: Icons.verified,
                    iconColor: AppColors.success,
                  ),
                  KpiCard(
                    title: 'Commerçants Actifs',
                    value: '${kpis['active_merchants_count'] ?? 0} / ${kpis['total_merchants_count'] ?? 0}',
                    subtitle: 'Points de vente actifs',
                    icon: Icons.storefront,
                    iconColor: AppColors.edahabiaGold,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w))).toList(),
                  );
                } else {
                  return Column(
                    children: items.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList(),
                  );
                }
              },
            ),
            const SizedBox(height: 24),

            // Risk Overview Banner / Card
            _buildRiskOverviewCard(riskDist),
            const SizedBox(height: 24),

            // Top Merchants Tables (2 columns on wide)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                return isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTopRevenueCard(topRev)),
                          const SizedBox(width: 20),
                          Expanded(child: _buildTopRejectionsCard(topRej)),
                        ],
                      )
                    : Column(
                        children: [
                          _buildTopRevenueCard(topRev),
                          const SizedBox(height: 20),
                          _buildTopRejectionsCard(topRej),
                        ],
                      );
              },
            ),
            if (summaryTables != null) _buildOfficialSummaryTables(summaryTables),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskOverviewCard(Map riskDist) {
    final low = (riskDist['low'] as num?)?.toInt() ?? 0;
    final med = (riskDist['medium'] as num?)?.toInt() ?? 0;
    final high = (riskDist['high'] as num?)?.toInt() ?? 0;
    final total = low + med + high;

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
                  Text('État Global du Risque & Alertes de Fraude', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Dossiers sous surveillance et détections heuristiques', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () => context.go('/a/risk'),
                icon: const Icon(Icons.security, size: 16),
                label: const Text('Ouvrir l\'Espace Risque'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Risk Donut
              SizedBox(
                height: 120,
                width: 120,
                child: total == 0
                    ? const Center(child: Text("0 alerte"))
                    : PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 32,
                          sections: [
                            PieChartSectionData(value: low.toDouble(), color: AppColors.success, radius: 24, showTitle: false),
                            PieChartSectionData(value: med.toDouble(), color: AppColors.warning, radius: 24, showTitle: false),
                            PieChartSectionData(value: high.toDouble(), color: AppColors.danger, radius: 24, showTitle: false),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  children: [
                    _buildRiskRow('Risque Élevé (Score ≥ 70)', high, AppColors.danger, high > 0 ? 'Action prioritaire requise' : 'Aucun dossier critique'),
                    const SizedBox(height: 8),
                    _buildRiskRow('Risque Modéré (Score 40-69)', med, AppColors.warning, 'Surveillance recommandée'),
                    const SizedBox(height: 8),
                    _buildRiskRow('Risque Faible (Score < 40)', low, AppColors.success, 'Profil standard'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRiskRow(String label, int count, Color color, String hint) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(hint, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ),
        Text('$count dossier${count > 1 ? 's' : ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
      ],
    );
  }

  Widget _buildTopRevenueCard(List list) {
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
          const Text('Top Commerçants par Chiffre d\'Affaires', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Plus forts contributeurs au volume du réseau', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const Text('Aucune transaction enregistrée')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length.clamp(0, 5),
              separatorBuilder: (ctx, i) => const Divider(height: 16),
              itemBuilder: (ctx, i) {
                final m = list[i];
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['business_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('${m['mcc_display'] ?? ''} • ${m['count'] ?? 0} tx', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Text(formatDzd(m['revenue'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTopRejectionsCard(List list) {
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
          const Text('Commerçants avec Rejets Élevés', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Surveillance des rejets techniques ou tentatives de fraude', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const Text('Aucun rejet notable')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length.clamp(0, 5),
              separatorBuilder: (ctx, i) => const Divider(height: 16),
              itemBuilder: (ctx, i) {
                final m = list[i];
                final rate = (m['rejection_rate'] as num?)?.toDouble() ?? 0.0;
                return Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                      child: const Icon(Icons.close, size: 14, color: AppColors.danger),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m['business_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('${m['rejected_count'] ?? 0} rejets / ${m['total_count'] ?? 0} total', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        formatPct(rate),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.danger),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOfficialSummaryTables(Map tables) {
    final statusList = (tables['status_breakdown'] as List?) ?? [];
    final channelList = (tables['channel_breakdown'] as List?) ?? [];
    final totalSummary = tables['total_summary'] as Map?;

    return Container(
      margin: const EdgeInsets.only(top: 24),
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.analytics, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Synthèse Analytique Officielle (Dataset FINOVIA)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  Text(
                    'Ventilation consolidée des 150 transactions par statut et canal de paiement',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final statusWidget = _buildStatusTable(statusList, totalSummary);
              final channelWidget = _buildChannelTable(channelList, totalSummary);

              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: statusWidget),
                        const SizedBox(width: 20),
                        Expanded(child: channelWidget),
                      ],
                    )
                  : Column(
                      children: [
                        statusWidget,
                        const SizedBox(height: 20),
                        channelWidget,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTable(List statusList, Map? totalSummary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Répartition par Statut', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.ink)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Statut', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('% Part', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Volume Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Ticket Moyen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: [
                ...statusList.map((row) {
                  final statusName = row['status'] ?? '-';
                  Color badgeColor = AppColors.ink;
                  if (statusName == 'Accepted') badgeColor = AppColors.success;
                  if (statusName == 'Declined') badgeColor = AppColors.danger;
                  if (statusName == 'Refunded') badgeColor = AppColors.cibBlue;
                  if (statusName == 'Cancelled') badgeColor = AppColors.warning;

                  return DataRow(cells: [
                    DataCell(Text(statusName, style: TextStyle(fontWeight: FontWeight.w600, color: badgeColor, fontSize: 12))),
                    DataCell(Text('${row['count'] ?? 0}', style: const TextStyle(fontSize: 12))),
                    DataCell(Text(formatPct((row['pct'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(formatDzd(row['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataCell(Text(formatDzd(row['avg_amount'] ?? 0), style: const TextStyle(fontSize: 12))),
                  ]);
                }),
                if (totalSummary != null)
                  DataRow(
                    color: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.05)),
                    cells: [
                      const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary))),
                      DataCell(Text('${totalSummary['total_count'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      const DataCell(Text('100,0 %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataCell(Text(formatDzd(totalSummary['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12))),
                      DataCell(Text(formatDzd(totalSummary['overall_avg'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTable(List channelList, Map? totalSummary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Répartition par Canal de Paiement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.ink)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Canal de Paiement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('% Part', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text('Volume Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              rows: [
                ...channelList.map((row) {
                  return DataRow(cells: [
                    DataCell(Text(row['channel'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                    DataCell(Text('${row['count'] ?? 0}', style: const TextStyle(fontSize: 12))),
                    DataCell(Text(formatPct((row['pct'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontSize: 12))),
                    DataCell(Text(formatDzd(row['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  ]);
                }),
                if (totalSummary != null)
                  DataRow(
                    color: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.05)),
                    cells: [
                      const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary))),
                      DataCell(Text('${totalSummary['total_count'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      const DataCell(Text('100,0 %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataCell(Text(formatDzd(totalSummary['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
