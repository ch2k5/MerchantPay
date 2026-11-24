import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/chart_utils.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantAnalyticsScreen extends ConsumerStatefulWidget {
  const MerchantAnalyticsScreen({super.key});

  @override
  ConsumerState<MerchantAnalyticsScreen> createState() => _MerchantAnalyticsScreenState();
}

class _MerchantAnalyticsScreenState extends ConsumerState<MerchantAnalyticsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPreset = 'all';
  String _granularity = 'daily';
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
        _error = "Impossible de charger les analyses statistiques avancées.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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

    if (_data == null) {
      return const AppEmptyState(
        title: "Données indisponibles",
        message: "Aucune donnée d'analyse disponible pour la période.",
      );
    }

    final kpis = _data!['kpis'] ?? {};
    final trends = (_data!['trends'] as List?) ?? [];
    final channelDist = _data!['channel_distribution'] ?? {};
    final channels = (channelDist['channels'] as List?) ?? [];
    final heatmap = _data!['heatmap'] ?? {};
    final matrix = (heatmap['matrix'] as List?) ?? [];
    final stats = _data!['statistics'] ?? {};
    final histogram = (stats['histogram'] as List?) ?? [];
    final boxplot = stats['boxplot'] ?? {};
    final scatterPoints = (stats['scatter_points'] as List?) ?? [];

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
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
                            'Intelligence & Analyses Statistiques',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Exploration visuelle des distributions, corrélations temporelles et détection d\'atypismes',
                            style: TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          DropdownButton<String>(
                            value: _selectedPreset,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('Tout le dataset')),
                              DropdownMenuItem(value: '7d', child: Text('7 derniers jours')),
                              DropdownMenuItem(value: '30d', child: Text('30 derniers jours (Mois)')),
                              DropdownMenuItem(value: '6m', child: Text('6 derniers mois')),
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
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: AppColors.slate),
                            tooltip: 'Actualiser les calculs',
                            onPressed: _fetchAnalytics,
                          ),
                        ],
                      ),
                    ],
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
                      Tab(icon: Icon(Icons.show_chart), text: "Évolution & Tendances"),
                      Tab(icon: Icon(Icons.bar_chart), text: "Distributions des Montants"),
                      Tab(icon: Icon(Icons.bubble_chart), text: "Nuage de Points & Corrélations"),
                      Tab(icon: Icon(Icons.grid_on), text: "Matrice Horaire 7×24"),
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
            _buildEvolutionTab(trends, channels, kpis),
            _buildDistributionTab(histogram, boxplot, kpis),
            _buildScatterTab(scatterPoints),
            _buildHeatmapTab(matrix, heatmap),
          ],
        ),
      ),
    );
  }

  // TAB 1: Evolution & Trends (Line chart + Comparative bar chart)
  Widget _buildEvolutionTab(List trends, List channels, Map kpis) {
    if (trends.isEmpty) {
      return const Center(child: Text("Pas assez de données pour tracer la tendance."));
    }

    final double maxRevenue = trends.fold(100.0, (m, t) => max(m, (t['net_revenue'] ?? t['volume'] ?? 0.0).toDouble()));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartCard(
            title: "Courbe d'Évolution du Chiffre d'Affaires Net (DZD)",
            subtitle: "Progression journalière avec lissage et identification des points hauts",
            guide: "Ce graphique retrace l'évolution temporelle de vos encaissements nets en dinars algériens. L'aire bleutée montre l'accumulation du volume d'affaires et les sommets mettent en évidence vos journées de plus forte affluence commerciale.",
            action: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Jour')),
                ButtonSegment(value: 'weekly', label: Text('Semaine')),
                ButtonSegment(value: 'monthly', label: Text('Mois')),
              ],
              selected: {_granularity},
              onSelectionChanged: (set) {
                setState(() => _granularity = set.first);
                _fetchAnalytics();
              },
            ),
            child: SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  lineTouchData: ChartUtils.lineTouchData(items: trends),
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
                        interval: max(1.0, (trends.length / 6).floorToDouble()),
                        getTitlesWidget: (idx, _) {
                          int i = idx.toInt();
                          if (i >= 0 && i < trends.length) {
                            final label = trends[i]['period_label'] ?? trends[i]['date'] ?? '';
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
                  maxY: maxRevenue * 1.15,
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

          // Comparison Bar Chart: CIB vs EDAHABIA
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _chartCard(
                  title: "Comparaison des Réseaux d'Acquisition (CIB vs EDAHABIA)",
                  subtitle: "Volume d'affaires capté et taux de succès par carte bancaire",
                  guide: "Ce graphique à barres compare les montants encaissés via la carte bancaire CIB (en bleu) et la carte postale EDAHABIA (en vert). Il vous indique quel réseau bancaire est privilégié par vos clients.",
                  child: SizedBox(
                    height: 220,
                    child: BarChart(
                      BarChartData(
                        barTouchData: ChartUtils.barTouchData(items: channels),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) {
                                int i = v.toInt();
                                if (i >= 0 && i < channels.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6.0),
                                    child: Text(channels[i]['channel_display'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  );
                                }
                                return const SizedBox();
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (int i = 0; i < channels.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: (channels[i]['accepted_amount'] ?? channels[i]['revenue'] ?? 0.0).toDouble(),
                                  color: i == 0 ? const Color(0xFF0D6EFD) : const Color(0xFF198754),
                                  width: 45,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
              Expanded(
                flex: 2,
                child: _chartCard(
                  title: "Indicateurs d'Acceptation",
                  subtitle: "Efficacité technique du réseau monétique",
                  guide: "Synthèse de performance de votre point d'encaissement : le taux de conversion mesure la part des ventes abouties et le panier moyen reflète la dépense typique par transaction.",
                  child: Column(
                    children: [
                      _statTile("Volume total encaissé", Formatters.formatDzd(kpis['net_revenue'] ?? kpis['accepted_amount'])),
                      const Divider(height: 20),
                      _statTile("Taux de conversion global", Formatters.formatPct(kpis['success_rate'])),
                      const Divider(height: 20),
                      _statTile("Taux de rejet technique", Formatters.formatPct(kpis['rejection_rate']), isAlert: (kpis['rejection_rate'] ?? 0) > 10),
                      const Divider(height: 20),
                      _statTile("Panier moyen de transaction", Formatters.formatDzd(kpis['avg_ticket'])),
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

  // TAB 2: Distribution & Boxplot
  Widget _buildDistributionTab(List histogram, Map boxplot, Map kpis) {
    if (histogram.isEmpty) {
      return const Center(child: Text("Données insuffisantes pour établir l'histogramme."));
    }

    final double maxHistCount = histogram.fold(1.0, (m, h) => max(m, (h['count'] ?? 0).toDouble()));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Histogram of amounts
          _chartCard(
            title: "Histogramme de Fréquence des Montants (DA)",
            subtitle: "Distribution statistique du montant des règlements traités sur la période",
            guide: "Cet histogramme regroupe vos transactions par tranches de montants en dinars. La hauteur de chaque colonne indique le nombre d'achats effectués dans cette tranche, révélant la gamme de prix la plus courante.",
            child: SizedBox(
              height: 260,
              child: BarChart(
                BarChartData(
                  barTouchData: ChartUtils.barTouchData(
                    items: histogram,
                    formatter: (i, v) => "${v.toInt()} transaction(s)",
                  ),
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxHistCount * 1.2,
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
                        reservedSize: 35,
                        getTitlesWidget: (v, _) => Text("${v.toInt()}", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (idx, _) {
                          int i = idx.toInt();
                          if (i >= 0 && i < histogram.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                "${histogram[i]['range_min'].toInt()} DA",
                                style: const TextStyle(fontSize: 9, color: AppColors.slate),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (int i = 0; i < histogram.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (histogram[i]['count'] ?? 0).toDouble(),
                            color: AppColors.primary,
                            width: 22,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Box Plot Summary & Dispersion Analysis
          _chartCard(
            title: "Analyse de Dispersion & Boîte à Moustaches (Box Plot)",
            subtitle: "Médiane, quartiles (Q1, Q3) et détection des valeurs extrêmes/atypiques",
            guide: "Statistique de Tukey : la barre centrale indique la Médiane (50 % des transactions sont en dessous). Le rectangle bleu regroupe le cœur de votre activité (50 % des ventes, entre Q1 et Q3). Les moustaches horizontales délimitent la dispersion normale et isolent les montants exceptionnels.",
            child: Column(
              children: [
                _buildBoxPlotDiagram(boxplot),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _boxMetric("Minimum", "${boxplot['min'] ?? 0} DA"),
                    _boxMetric("1er Quartile (Q1)", "${boxplot['q1'] ?? 0} DA"),
                    _boxMetric("Médiane", "${boxplot['median'] ?? 0} DA", isBold: true),
                    _boxMetric("3ème Quartile (Q3)", "${boxplot['q3'] ?? 0} DA"),
                    _boxMetric("Maximum", "${boxplot['max'] ?? 0} DA"),
                    _boxMetric("Valeurs Atypiques", "${boxplot['outliers_count'] ?? 0}", isAlert: (boxplot['outliers_count'] ?? 0) > 0),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3: Scatter Plot (Amount vs Time / Outlier correlation)
  Widget _buildScatterTab(List scatterPoints) {
    if (scatterPoints.isEmpty) {
      return const Center(child: Text("Aucune transaction trouvée pour le nuage de points."));
    }

    final double maxAmount = scatterPoints.fold(100.0, (m, p) => max(m, (p['amount'] ?? 0.0).toDouble()));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartCard(
            title: "Nuage de Points : Montant des Opérations Récentes",
            subtitle: "Repérage instantané des montants aberrants, rejets techniques et corrélations",
            guide: "Chaque point représente une transaction individuelle positionnée selon son ordre chronologique et son montant en DA. Vert = Acceptée, Rouge = Rejetée, Orange = Remboursée, Gris = Annulée. Permet d'isoler en un clin d'œil les montants anormaux ou les rejets groupés.",
            child: SizedBox(
              height: 320,
              child: ScatterChart(
                ScatterChartData(
                  scatterTouchData: ChartUtils.scatterTouchData(items: scatterPoints),
                  minX: 0,
                  maxX: scatterPoints.length.toDouble(),
                  minY: 0,
                  maxY: maxAmount * 1.15,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.8),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: max(1.0, (scatterPoints.length / 5).floorToDouble()),
                        getTitlesWidget: (v, _) => Text("T-${scatterPoints.length - v.toInt()}", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 55,
                        getTitlesWidget: (v, _) => Text("${(v / 1000).toInt()}k", style: const TextStyle(fontSize: 10, color: AppColors.slate)),
                      ),
                    ),
                  ),
                  scatterSpots: [
                    for (int i = 0; i < scatterPoints.length; i++)
                      ScatterSpot(
                        i.toDouble(),
                        (scatterPoints[i]['amount'] ?? 0.0).toDouble(),
                        dotPainter: FlDotCirclePainter(
                          radius: 5,
                          color: _statusColor(scatterPoints[i]['status']),
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legendDot(const Color(0xFF198754), "Acceptée"),
              const SizedBox(width: 24),
              _legendDot(const Color(0xFFDC3545), "Rejetée / Échouée"),
              const SizedBox(width: 24),
              _legendDot(const Color(0xFFFD7E14), "Remboursée"),
              const SizedBox(width: 24),
              _legendDot(const Color(0xFF6C757D), "Annulée"),
            ],
          ),
        ],
      ),
    );
  }

  // TAB 4: Heatmap 7x24 Matrix
  Widget _buildHeatmapTab(List matrix, Map heatmap) {
    if (matrix.isEmpty) {
      return const Center(child: Text("Données de matrice horaire indisponibles."));
    }

    final int maxCount = matrix.fold(1, (m, c) => max(m, (c['count'] ?? 0) as int));
    final peakSlot = heatmap['peak_slot'] ?? {};
    final lowSlot = heatmap['low_slot'] ?? {};

    final dayNames = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _peakBanner("Créneau de pointe (Affluence max)", "${peakSlot['day_name'] ?? 'Dimanche'} à ${peakSlot['hour'] ?? 12}h00 (${peakSlot['count'] ?? 0} tx)", Icons.local_fire_department, Colors.orange),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _peakBanner("Créneau creux d'activité", "${lowSlot['day_name'] ?? 'Dimanche'} à ${lowSlot['hour'] ?? 8}h00 (${lowSlot['count'] ?? 0} tx)", Icons.nights_stay, Colors.blueGrey),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _chartCard(
            title: "Matrice d'Intensité Monétique (7 jours × 24 heures)",
            subtitle: "Densité du trafic électronique pour ajuster vos créneaux et effectifs",
            guide: "Carte thermique des 168 heures de la semaine (7 jours × 24h). Plus la couleur bleue est soutenue, plus le nombre de paiements enregistrés à cette heure précise est important. Idéal pour optimiser vos horaires d'ouverture et vos effectifs.",
            child: Column(
              children: [
                // Hours header
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

                // Heatmap Rows
                for (int d = 0; d < 7; d++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 45,
                          child: Text(dayNames[d], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink)),
                        ),
                        for (int h = 0; h < 24; h++)
                          Expanded(
                            child: _buildHeatCell(matrix, d, h, maxCount),
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

  Widget _buildHeatCell(List matrix, int d, int h, int maxCount) {
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
      message: "$count tx ($h:00)",
      child: Container(
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 1.0),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
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
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Lower whisker
          Expanded(
            flex: max(1, (leftWhiskerWidth * 100).toInt()),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Divider(color: AppColors.slate, thickness: 2),
                Align(alignment: Alignment.centerLeft, child: Container(width: 3, height: 24, color: AppColors.slate)),
              ],
            ),
          ),
          // IQR Box
          Expanded(
            flex: max(2, (boxWidth * 100).toInt()),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Container(width: 3, height: 38, color: AppColors.primary),
              ),
            ),
          ),
          // Upper whisker
          Expanded(
            flex: max(1, (rightWhiskerWidth * 100).toInt()),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Divider(color: AppColors.slate, thickness: 2),
                Align(alignment: Alignment.centerRight, child: Container(width: 3, height: 24, color: AppColors.slate)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? action,
    String? guide,
  }) {
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              ?action,
            ],
          ),
          if (guide != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guide,
                      style: const TextStyle(fontSize: 11, color: AppColors.slate, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, {bool isAlert = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isAlert ? AppColors.danger : AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _boxMetric(String label, String value, {bool isBold = false, bool isAlert = false}) {
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

  Widget _peakBanner(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.ink)),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'ACCEPTED':
        return const Color(0xFF198754);
      case 'REJECTED':
        return const Color(0xFFDC3545);
      case 'REFUNDED':
        return const Color(0xFFFD7E14);
      default:
        return const Color(0xFF6C757D);
    }
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slate)),
      ],
    );
  }
}
