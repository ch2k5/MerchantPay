import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/kpi_card.dart';

class AdminAnalyticsScreen extends ConsumerStatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  ConsumerState<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends ConsumerState<AdminAnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPreset = '30d';
  String _selectedGranularity = 'day';
  String _selectedCategory = 'ALL';
  String _selectedChannel = 'ALL';
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchAnalytics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{
        'preset': _selectedPreset,
        'granularity': _selectedGranularity,
      };
      if (_selectedCategory != 'ALL') {
        query['category'] = _selectedCategory;
      }
      if (_selectedChannel != 'ALL') {
        query['channel'] = _selectedChannel;
      }

      final res = await client.get('/admin/analytics/', queryParameters: query);
      if (res.statusCode == 200) {
        setState(() {
          _data = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de charger les analyses statistiques globales.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _export(String format) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Génération du rapport d'analyses $format...")),
    );
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get(
        '/admin/analytics/export/',
        queryParameters: {
          'format': format,
          'preset': _selectedPreset,
        },
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text("Rapport $format généré et téléchargé avec succès !"),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text("Échec du téléchargement du rapport $format."),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _data == null) {
      return AppErrorState(message: _error!, onRetry: _fetchAnalytics);
    }

    final overview = _data?['overview'] ?? {};
    final temporal = _data?['temporal'] ?? {};
    final merchantsAnalysis = _data?['merchants_analysis'] ?? {};
    final txAnalysis = _data?['transactions_analysis'] ?? {};

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
                      'Analyses & Statistiques Réseau',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                    Text(
                      'Espace analytique consolidé SATIM — CIB & EDAHABIA sur l\'ensemble du territoire',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _export('csv'),
                      icon: const Icon(Icons.table_view, size: 16),
                      label: const Text('Export CSV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _export('pdf'),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('Rapport PDF'),
                    ),
                    FilledButton.icon(
                      onPressed: _fetchAnalytics,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Actualiser'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Bar
            _buildFilterBar(),
            const SizedBox(height: 20),

            // Tab Bar
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_outlined), text: "1. Vue d'ensemble"),
                  Tab(icon: Icon(Icons.schedule_outlined), text: "2. Analyse Temporelle"),
                  Tab(icon: Icon(Icons.storefront_outlined), text: "3. Analyse Commerçants"),
                  Tab(icon: Icon(Icons.payments_outlined), text: "4. Analyse Transactions"),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tab Body (Switchable content)
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                switch (_tabController.index) {
                  case 0:
                    return _buildOverviewSection(overview);
                  case 1:
                    return _buildTemporalSection(temporal);
                  case 2:
                    return _buildMerchantsSection(merchantsAnalysis);
                  case 3:
                    return _buildTransactionsSection(txAnalysis);
                  default:
                    return _buildOverviewSection(overview);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Period Preset
          PeriodSelectorWidget(
            currentPreset: _selectedPreset,
            onPresetChanged: (p) {
              setState(() => _selectedPreset = p);
              _fetchAnalytics();
            },
          ),
          const SizedBox(width: 8),

          // Granularity Selector
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Jour')),
              ButtonSegment(value: 'week', label: Text('Semaine')),
              ButtonSegment(value: 'month', label: Text('Mois')),
            ],
            selected: {_selectedGranularity},
            onSelectionChanged: (set) {
              setState(() => _selectedGranularity = set.first);
              _fetchAnalytics();
            },
          ),
          const SizedBox(width: 8),

          // Channel filter
          DropdownButton<String>(
            value: _selectedChannel,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('Tous canaux')),
              DropdownMenuItem(value: 'E-commerce (CIB / Edahabia)', child: Text('E-commerce')),
              DropdownMenuItem(value: 'TPE / POS Terminal', child: Text('TPE / POS')),
              DropdownMenuItem(value: 'Mobile App', child: Text('Mobile App')),
              DropdownMenuItem(value: 'Contactless / NFC', child: Text('Sans Contact')),
              DropdownMenuItem(value: 'Bank Transfer / Virement', child: Text('Virement')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedChannel = v);
                _fetchAnalytics();
              }
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SECTION 1: VUE D'ENSEMBLE
  // ==========================================
  Widget _buildOverviewSection(Map overview) {
    final comp = overview['comparison'] ?? {};
    final netRevDelta = comp['net_revenue']?['delta_pct'] as num?;
    final countDelta = comp['total_transactions']?['delta_pct'] as num?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 Key Metric Cards
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final items = [
              KpiCard(
                title: 'Volume Traité (Net)',
                value: formatDzd(overview['net_revenue'] ?? 0),
                deltaPct: netRevDelta?.toDouble(),
                subtitle: 'Encaissements compensés SATIM',
                icon: Icons.account_balance_wallet,
                iconColor: AppColors.primary,
              ),
              KpiCard(
                title: 'Nombre de Transactions',
                value: '${overview['total_transactions'] ?? 0}',
                deltaPct: countDelta?.toDouble(),
                subtitle: 'Opérations réseau globales',
                icon: Icons.receipt_long,
                iconColor: AppColors.cibBlue,
              ),
              KpiCard(
                title: 'Taux d\'Acceptation',
                value: formatPct(overview['success_rate'] ?? 0),
                subtitle: 'Taux de rejet : ${formatPct(overview['rejection_rate'] ?? 0)}',
                icon: Icons.check_circle_outline,
                iconColor: AppColors.success,
              ),
              KpiCard(
                title: 'Points de Vente Actifs',
                value: '${overview['active_merchants'] ?? 0} / ${overview['total_merchants'] ?? 0}',
                subtitle: 'Commerçants connectés au réseau',
                icon: Icons.storefront,
                iconColor: AppColors.edahabiaGold,
              ),
            ];

            return isWide
                ? Row(
                    children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w))).toList(),
                  )
                : Column(
                    children: items.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList(),
                  );
          },
        ),
        const SizedBox(height: 24),

        // Summary Statistics Grid
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Indicateurs Consolidés de Performance Réseau', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Métriques agrégées sur la période d\'observation', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 30,
                runSpacing: 16,
                children: [
                  _statItem('Ticket Moyen Global', formatDzd(overview['avg_ticket'] ?? 0)),
                  _statItem('Transactions Acceptées', '${overview['accepted_count'] ?? 0} tx'),
                  _statItem('Transactions Refusées', '${overview['rejected_count'] ?? 0} tx', isAlert: true),
                  _statItem('Transactions Remboursées', '${overview['refunded_count'] ?? 0} tx'),
                  _statItem('Transactions Annulées', '${overview['cancelled_count'] ?? 0} tx'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, {bool isAlert = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isAlert ? AppColors.danger : AppColors.ink,
          ),
        ),
      ],
    );
  }

  // ==========================================
  // SECTION 2: ANALYSE TEMPORELLE
  // ==========================================
  Widget _buildTemporalSection(Map temporal) {
    final trends = (temporal['trends'] as List?) ?? [];
    final heatmap = temporal['heatmap'] ?? {};
    final matrix = (heatmap['matrix'] as List?) ?? [];
    final peakSlot = heatmap['peak_slot'] ?? {};
    final lowSlot = heatmap['low_slot'] ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trends Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Évolution Temporelle du Volume d\'Encaissement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Trajectoire des montants acceptés sur le réseau', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 24),
              SizedBox(
                height: 240,
                child: trends.isEmpty
                    ? const Center(child: Text("Données insuffisantes"))
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
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 32,
                                interval: (trends.length / 6).clamp(1.0, 10.0),
                                getTitlesWidget: (val, meta) {
                                  final idx = val.toInt();
                                  if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                                  final label = trends[idx]['label']?.toString() ?? '';
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                                  );
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
        ),
        const SizedBox(height: 24),

        // Peak / Low callouts
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_up, color: AppColors.success, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pic d\'Affluence Réseau (Heure de Pointe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.success)),
                          const SizedBox(height: 2),
                          Text(
                            '${peakSlot['day_name'] ?? peakSlot['day'] ?? 'Dimanche'} à ${peakSlot['hour'] ?? 12}h (${peakSlot['count'] ?? 0} transactions)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.nightlight_round, color: AppColors.warning, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Créneau d\'Activité Creuse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.warning)),
                          const SizedBox(height: 2),
                          Text(
                            '${lowSlot['day_name'] ?? lowSlot['day'] ?? 'Dimanche'} à ${lowSlot['hour'] ?? 4}h (${lowSlot['count'] ?? 0} transactions)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Heatmap Grid 7j x 24h
        _buildHeatmapGrid(matrix),
      ],
    );
  }

  Widget _buildHeatmapGrid(List matrix) {
    final days = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
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
                  Text('Matrice Temporelle 7j / 24h', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Densité des transactions réseau par jour de semaine et heure', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
                              (c) => c is Map && c['hour'] == h,
                              orElse: () => {'count': 0},
                            );
                            final count = (cell['count'] as num?)?.toInt() ?? 0;
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
                                message: '$dayName à ${h}h : $count transactions',
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

  // ==========================================
  // SECTION 3: ANALYSE DES COMMERÇANTS
  // ==========================================
  Widget _buildMerchantsSection(Map merchantsAnalysis) {
    final topVolume = (merchantsAnalysis['top_by_volume'] as List?) ?? [];
    final topRejections = (merchantsAnalysis['top_by_rejections'] as List?) ?? [];
    final categoryPerf = (merchantsAnalysis['category_performance'] as List?) ?? [];
    final anomalies = (merchantsAnalysis['anomalous_merchants'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Anomalies Banner if any
        if (anomalies.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Comportements Atypiques / Rejets Élevés Détectés', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.danger)),
                      const SizedBox(height: 2),
                      Text(
                        '${anomalies.length} commerçant(s) présentent un taux de rejet supérieur à 25 % sur la période.',
                        style: const TextStyle(fontSize: 12, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // 2 Columns: Top Volume vs Top Rejections
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 850;
            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildTopVolumeTable(topVolume)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildTopRejectionsTable(topRejections)),
                    ],
                  )
                : Column(
                    children: [
                      _buildTopVolumeTable(topVolume),
                      const SizedBox(height: 20),
                      _buildTopRejectionsTable(topRejections),
                    ],
                  );
          },
        ),
        const SizedBox(height: 24),

        // Category Performance Table
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Performance par Secteur d\'Activité', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: 4),
              const Text('Volume, part de marché et taux de rejet par catégorie', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Secteur')),
                    DataColumn(label: Text('Transactions')),
                    DataColumn(label: Text('Volume Total')),
                    DataColumn(label: Text('Part (%)')),
                    DataColumn(label: Text('Ticket Moyen')),
                    DataColumn(label: Text('Taux Rejet')),
                  ],
                  rows: categoryPerf.map((cat) {
                    final rejRate = (cat['rejection_rate'] as num?)?.toDouble() ?? 0.0;
                    return DataRow(cells: [
                      DataCell(Text(cat['category'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('${cat['total_count'] ?? 0}')),
                      DataCell(Text(formatDzd(cat['volume'] ?? 0))),
                      DataCell(Text(formatPct((cat['share_pct'] as num?)?.toDouble() ?? 0))),
                      DataCell(Text(formatDzd(cat['avg_ticket'] ?? 0))),
                      DataCell(
                        Text(
                          formatPct(rejRate),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: rejRate > 20 ? AppColors.danger : AppColors.ink,
                          ),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopVolumeTable(List list) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Commerçants par Chiffre d\'Affaires', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length.clamp(0, 6),
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (ctx, i) {
              final m = list[i];
              return Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${m['category']} • ${m['wilaya']}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Text(formatDzd(m['volume'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTopRejectionsTable(List list) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Commerçants avec Rejets Significatifs', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length.clamp(0, 6),
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (ctx, i) {
              final m = list[i];
              final rate = (m['rejection_rate'] as num?)?.toDouble() ?? 0.0;
              return Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                    child: const Icon(Icons.close, size: 12, color: AppColors.danger),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${m['rejected_count']} rejets / ${m['total_count']} tx', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(formatPct(rate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.danger)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SECTION 4: ANALYSE DES TRANSACTIONS
  // ==========================================
  Widget _buildTransactionsSection(Map txAnalysis) {
    final statusDist = (txAnalysis['status_distribution'] as List?) ?? [];
    final channelDist = (txAnalysis['channel_distribution'] as List?) ?? [];
    final amountBrackets = (txAnalysis['amount_brackets'] as List?) ?? [];
    final rejectionReasons = (txAnalysis['rejection_reasons'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2 Columns: Status Distribution & Channel Distribution
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 850;
            return isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDistributionCard('Répartition par Statut', statusDist, isStatus: true)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildDistributionCard('Répartition par Canal de Paiement', channelDist, isStatus: false)),
                    ],
                  )
                : Column(
                    children: [
                      _buildDistributionCard('Répartition par Statut', statusDist, isStatus: true),
                      const SizedBox(height: 20),
                      _buildDistributionCard('Répartition par Canal de Paiement', channelDist, isStatus: false),
                    ],
                  );
          },
        ),
        const SizedBox(height: 24),

        // Amount Brackets
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ventilation par Tranche de Montant (DZD)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
              const SizedBox(height: 4),
              const Text('Répartition de la valeur des paniers sur l\'ensemble du réseau', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 20),
              Column(
                children: amountBrackets.map((b) {
                  final pct = (b['pct'] as num?)?.toDouble() ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(b['label'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${b['count']} tx (${formatPct(pct)})', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: AppColors.primary,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Rejection Reasons Breakdown
        if (rejectionReasons.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Motifs Principaux de Rejet & Échecs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 4),
                const Text('Causes d\'échec déclarées par les passerelles et banques émettrices', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rejectionReasons.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (ctx, i) {
                    final r = rejectionReasons[i];
                    return Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(r['reason'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        ),
                        Text('${r['count']} rejets (${formatPct((r['pct'] as num?)?.toDouble() ?? 0)})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.danger)),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDistributionCard(String title, List items, {required bool isStatus}) {
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
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 12),
            itemBuilder: (ctx, i) {
              final it = items[i];
              final name = isStatus ? (it['status'] ?? '-') : (it['channel'] ?? '-');
              Color color = AppColors.ink;
              if (name == 'Accepted') color = AppColors.success;
              if (name == 'Declined') color = AppColors.danger;
              if (name == 'Refunded') color = AppColors.cibBlue;
              if (name == 'Cancelled') color = AppColors.warning;

              return Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color)),
                  ),
                  Text('${it['count'] ?? 0} tx', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(width: 12),
                  Text(formatDzd(it['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
