import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/file_saver.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';

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
      SnackBar(content: Text("Génération de l'export statistique $format...")),
    );
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.dio.get<List<int>>(
        '/admin/reports/generate/',
        queryParameters: {
          'report_type': 'MONTHLY_VOLUME',
          'format': format,
          'preset': _selectedPreset,
        },
      );
      if (res.statusCode == 200 && res.data != null && mounted) {
        final bytes = res.data!;
        final mimeType = format == 'pdf' ? 'application/pdf' : 'text/csv;charset=utf-8';
        final filename = 'analyses_statistiques_satim.$format';

        saveFile(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        );

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
    final transactionsAnalysis = _data?['transactions_analysis'] ?? {};
    final fraudAnalytics = _data?['fraud_analytics'] ?? {};

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Observatoire Statistique & Monétique SATIM',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Supervision globale par représentations graphiques, histogrammes et corrélation du risque',
                            style: TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.picture_as_pdf, size: 16),
                            label: const Text("Export PDF"),
                            onPressed: () => _export('pdf'),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.table_chart, size: 16),
                            label: const Text("Export CSV"),
                            onPressed: () => _export('csv'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: AppColors.slate),
                            onPressed: _fetchAnalytics,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Filters row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        _dropdownControl(
                          label: "Période",
                          value: _selectedPreset,
                          items: const [
                            DropdownMenuItem(value: '7d', child: Text('7 derniers jours')),
                            DropdownMenuItem(value: '30d', child: Text('30 derniers jours (Mois)')),
                            DropdownMenuItem(value: '90d', child: Text('90 derniers jours (Trimestre)')),
                            DropdownMenuItem(value: 'ytd', child: Text('Année en cours (YTD)')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedPreset = v);
                              _fetchAnalytics();
                            }
                          },
                        ),
                        _dropdownControl(
                          label: "Canal",
                          value: _selectedChannel,
                          items: const [
                            DropdownMenuItem(value: 'ALL', child: Text('Tous les canaux')),
                            DropdownMenuItem(value: 'CIB', child: Text('Réseau CIB')),
                            DropdownMenuItem(value: 'EDAHABIA', child: Text('Réseau EDAHABIA')),
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
                  ),
                  const SizedBox(height: 16),

                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.slate,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 3,
                    tabs: const [
                      Tab(icon: Icon(Icons.insights), text: "Activité & Évolution"),
                      Tab(icon: Icon(Icons.storefront), text: "Comportement Commerçants"),
                      Tab(icon: Icon(Icons.bar_chart), text: "Distributions des Transactions"),
                      Tab(icon: Icon(Icons.security), text: "Analyse des Risques & Anomalies"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildPlatformActivityTab(overview, temporal),
            _buildMerchantBehaviorTab(merchantsAnalysis),
            _buildTransactionStatisticsTab(transactionsAnalysis),
            _buildFraudAnomalyTab(fraudAnalytics),
          ],
        ),
      ),
    );
  }

  // PILLAR 1: Platform Activity (Volume & Count Line Chart + Heatmap)
  Widget _buildPlatformActivityTab(Map overview, Map temporal) {
    final trends = (temporal['trends'] as List?) ?? [];
    final heatmap = temporal['heatmap'] ?? {};
    final matrix = (heatmap['matrix'] as List?) ?? [];
    final maxVol = trends.fold(100.0, (m, t) => max(m, (t['net_revenue'] ?? t['volume'] ?? 0.0).toDouble()));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartCard(
            title: "Tendance Globale des Flux Monétiques Interbancaires",
            subtitle: "Évolution temporelle du volume net (DZD) traité sur les serveurs SATIM",
            child: SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
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
                        reservedSize: 60,
                        getTitlesWidget: (v, _) => Text("${(v / 1000).toInt()}k", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: max(1.0, (trends.length / 6).floorToDouble()),
                        getTitlesWidget: (idx, _) {
                          int i = idx.toInt();
                          if (i >= 0 && i < trends.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                (trends[i]['period_label'] ?? trends[i]['date'] ?? '').toString().split(' ').first,
                                style: const TextStyle(fontSize: 10, color: AppColors.slate),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: maxVol * 1.15,
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < trends.length; i++)
                          FlSpot(i.toDouble(), (trends[i]['net_revenue'] ?? trends[i]['volume'] ?? 0.0).toDouble()),
                      ],
                      isCurved: true,
                      color: AppColors.primary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Heatmap
          _chartCard(
            title: "Matrice d'Intensité Temporelle Nationale (7×24)",
            subtitle: "Charge transactionnelle par heure et jour de la semaine sur le switch monétique",
            child: _buildHeatmapGrid(matrix),
          ),
        ],
      ),
    );
  }

  // PILLAR 2: Merchant Behavior (Horizontal Bar chart of Top merchants + Category comparison)
  Widget _buildMerchantBehaviorTab(Map merchantsAnalysis) {
    final topMerchants = (merchantsAnalysis['top_by_volume'] as List?) ?? [];
    final categories = (merchantsAnalysis['category_performance'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top merchants horizontal bar chart
              Expanded(
                flex: 3,
                child: _chartCard(
                  title: "Classement des Commerçants par Chiffre d'Affaires Net (DZD)",
                  subtitle: "Top 7 des volumes d'encaissement les plus significatifs du réseau",
                  child: Column(
                    children: [
                      for (int i = 0; i < min(7, topMerchants.length); i++) ...[
                        _buildHorizontalBar(
                          label: topMerchants[i]['name'] ?? '',
                          category: topMerchants[i]['category'] ?? '',
                          amount: (topMerchants[i]['volume'] ?? 0.0).toDouble(),
                          maxAmount: (topMerchants.first['volume'] ?? 100.0).toDouble(),
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Category breakdown
              Expanded(
                flex: 2,
                child: _chartCard(
                  title: "Volumes par Secteur d'Activité",
                  subtitle: "Part relative des catégories commerciales",
                  child: Column(
                    children: [
                      for (final cat in categories.take(5)) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(cat['category'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text("${cat['share_pct']}%", style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (cat['share_pct'] ?? 0.0) / 100.0,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: AppColors.primary,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PILLAR 3: Transaction Statistics (Histogram, Status pie/bar, Outlier Box Plot)
  Widget _buildTransactionStatisticsTab(Map transactionsAnalysis) {
    final stats = transactionsAnalysis['statistical_distribution'] ?? {};
    final histogram = (stats['histogram'] as List?) ?? [];
    final boxplot = stats['boxplot'] ?? {};
    final brackets = (transactionsAnalysis['amount_brackets'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Histogram
              Expanded(
                flex: 3,
                child: _chartCard(
                  title: "Histogramme de Fréquence des Montants (DA)",
                  subtitle: "Densité probabiliste des montants réglés par carte CIB et EDAHABIA",
                  child: SizedBox(
                    height: 250,
                    child: BarChart(
                      BarChartData(
                        maxY: histogram.fold(1.0, (m, h) => max(m, (h['count'] ?? 0).toDouble())) * 1.2,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (v, _) {
                                int i = v.toInt();
                                if (i >= 0 && i < histogram.length) {
                                  return Text("${histogram[i]['range_min'].toInt()} DA", style: const TextStyle(fontSize: 9, color: AppColors.slate));
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (int i = 0; i < histogram.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: (histogram[i]['count'] ?? 0).toDouble(),
                                  color: AppColors.primary,
                                  width: 24,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Status Distribution
              Expanded(
                flex: 2,
                child: _chartCard(
                  title: "Tranches de Montants Usuelles",
                  subtitle: "Proportion des paniers d'achat",
                  child: Column(
                    children: [
                      for (final b in brackets) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(b['label'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.ink)),
                            Text("${b['pct']}% (${b['count']} tx)", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (b['pct'] ?? 0.0) / 100.0,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: const Color(0xFF0D6EFD),
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Boxplot Outlier Card
          _chartCard(
            title: "Boîte à Moustaches (Box Plot) & Détection des Valeurs Atypiques",
            subtitle: "Repérage des transactions excédant 1.5× l'intervalle interquartile (IQR)",
            child: Column(
              children: [
                _buildBoxPlotDiagram(boxplot),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricItem("Min", "${boxplot['min'] ?? 0} DA"),
                    _metricItem("Q1 (25%)", "${boxplot['q1'] ?? 0} DA"),
                    _metricItem("Médiane", "${boxplot['median'] ?? 0} DA", isBold: true),
                    _metricItem("Q3 (75%)", "${boxplot['q3'] ?? 0} DA"),
                    _metricItem("Max", "${boxplot['max'] ?? 0} DA"),
                    _metricItem("Outliers", "${boxplot['outliers_count'] ?? 0}", isAlert: (boxplot['outliers_count'] ?? 0) > 0),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // PILLAR 4: Fraud & Anomaly Analytics (Risk Score Histogram + Risk vs Amount Scatter)
  Widget _buildFraudAnomalyTab(Map fraudAnalytics) {
    final scoreDistribution = (fraudAnalytics['score_distribution'] as List?) ?? [];
    final scatterRisk = (fraudAnalytics['scatter_risk_vs_amount'] as List?) ?? [];
    final velocityStats = (fraudAnalytics['velocity_stats'] as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Risk score distribution
              Expanded(
                flex: 3,
                child: _chartCard(
                  title: "Distribution des Scores de Risque Fraude (/100)",
                  subtitle: "Ventilation des signalements selon la sévérité déterminée par le moteur heuristique",
                  child: Column(
                    children: [
                      for (final b in scoreDistribution) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(color: Color(int.parse(b['color'].replaceAll('#', '0xFF'))), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(b['range'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Text("${b['count']} dossiers (${b['pct']}%)", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (b['pct'] ?? 0.0) / 100.0,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: Color(int.parse(b['color'].replaceAll('#', '0xFF'))),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Velocity Breakdown
              Expanded(
                flex: 2,
                child: _chartCard(
                  title: "Distribution de la Vélocité Transactionnelle",
                  subtitle: "Analyse des rafales de transactions",
                  child: Column(
                    children: [
                      for (final v in velocityStats) ...[
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            v['is_anomaly'] ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            color: v['is_anomaly'] ? AppColors.danger : AppColors.success,
                          ),
                          title: Text(v['label'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          trailing: Text("${v['count']} obs.", style: const TextStyle(fontSize: 12, color: AppColors.slate)),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Scatter Plot: Risk Score vs Transaction Amount
          _chartCard(
            title: "Nuage de Corrélation : Score de Risque vs Montant de Transaction",
            subtitle: "Isolement visuel des anomalies à fort impact financier",
            child: SizedBox(
              height: 280,
              child: ScatterChart(
                ScatterChartData(
                  minX: 0,
                  maxX: 100,
                  minY: 0,
                  maxY: 60000,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.8),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 20,
                        getTitlesWidget: (v, _) => Text("Score ${v.toInt()}", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: 15000,
                        getTitlesWidget: (v, _) => Text("${(v / 1000).toInt()}k DA", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  scatterSpots: [
                    for (int i = 0; i < scatterRisk.length; i++)
                      ScatterSpot(
                        (scatterRisk[i]['risk_score'] ?? 0).toDouble(),
                        (scatterRisk[i]['amount'] ?? 1000.0).toDouble().clamp(0.0, 60000.0),
                        dotPainter: FlDotCirclePainter(
                          radius: (scatterRisk[i]['risk_score'] ?? 0) > 70 ? 7 : 4,
                          color: (scatterRisk[i]['risk_score'] ?? 0) > 70 ? const Color(0xFFDC3545) : const Color(0xFFFFC107),
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid(List matrix) {
    if (matrix.isEmpty) {
      return const Center(child: Text("Matrice indisponible."));
    }
    final int maxCount = matrix.fold(1, (m, c) => max(m, (c['count'] ?? 0) as int));
    final dayNames = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 45),
            for (int h = 0; h < 24; h += 2)
              Expanded(
                child: Text("${h}h", textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.slate)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (int d = 0; d < 7; d++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                SizedBox(
                  width: 45,
                  child: Text(dayNames[d], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink)),
                ),
                for (int h = 0; h < 24; h++) ...[
                  Expanded(
                    child: _heatCell(matrix, d, h, maxCount),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _heatCell(List matrix, int d, int h, int maxCount) {
    final cell = matrix.firstWhere(
      (it) => it['day_index'] == d && it['hour'] == h,
      orElse: () => {'count': 0},
    );
    final count = cell['count'] ?? 0;
    final ratio = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;
    final color = count == 0
        ? const Color(0xFFF1F5F9)
        : AppColors.primary.withValues(alpha: 0.15 + (ratio * 0.85));

    return Tooltip(
      message: "$count transactions nationales à $h:00",
      child: Container(
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }

  Widget _buildHorizontalBar({
    required String label,
    required String category,
    required double amount,
    required double maxAmount,
    required Color color,
  }) {
    final ratio = maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.ink)),
            Text(Formatters.formatDzd(amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.ink)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: const Color(0xFFF1F5F9),
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBoxPlotDiagram(Map boxplot) {
    final minVal = (boxplot['min'] ?? 0).toDouble();
    final q1Val = (boxplot['q1'] ?? 0).toDouble();
    final q3Val = (boxplot['q3'] ?? 0).toDouble();
    final maxVal = (boxplot['max'] ?? 100).toDouble();

    final range = max(1.0, maxVal - minVal);
    final leftWhiskerWidth = max(0.0, ((q1Val - minVal) / range));
    final boxWidth = max(0.05, ((q3Val - q1Val) / range));
    final rightWhiskerWidth = max(0.0, ((maxVal - q3Val) / range));

    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            flex: max(1, (leftWhiskerWidth * 100).toInt()),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Divider(color: AppColors.slate, thickness: 2),
                Align(alignment: Alignment.centerLeft, child: Container(width: 3, height: 22, color: AppColors.slate)),
              ],
            ),
          ),
          Expanded(
            flex: max(2, (boxWidth * 100).toInt()),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Container(width: 3, height: 36, color: AppColors.primary),
              ),
            ),
          ),
          Expanded(
            flex: max(1, (rightWhiskerWidth * 100).toInt()),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Divider(color: AppColors.slate, thickness: 2),
                Align(alignment: Alignment.centerRight, child: Container(width: 3, height: 22, color: AppColors.slate)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({required String title, required String subtitle, required Widget child}) {
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
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, {bool isBold = false, bool isAlert = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isAlert ? AppColors.danger : AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _dropdownControl({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("$label : ", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate)),
        DropdownButton<String>(
          value: value,
          isDense: true,
          underline: const SizedBox(),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
