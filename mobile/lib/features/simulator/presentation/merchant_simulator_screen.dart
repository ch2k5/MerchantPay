import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantSimulatorScreen extends ConsumerStatefulWidget {
  const MerchantSimulatorScreen({super.key});

  @override
  ConsumerState<MerchantSimulatorScreen> createState() => _MerchantSimulatorScreenState();
}

class _MerchantSimulatorScreenState extends ConsumerState<MerchantSimulatorScreen> {
  double _volumePct = 15.0; // -50 to +200%
  double _ticketDelta = 0.0; // -5000 to +10000 DZD
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _simResult;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _runSimulation();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onParamsChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSimulation();
    });
  }

  Future<void> _runSimulation() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post(
        '/merchant/simulator/',
        data: {
          'volume_pct': _volumePct,
          'growth_rate_pct': _volumePct,
          'ticket_delta': _ticketDelta,
          'avg_amount_delta_dzd': _ticketDelta,
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          _simResult = res.data;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de calculer la simulation.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _volumePct = 0.0;
      _ticketDelta = 0.0;
    });
    _runSimulation();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _simResult == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _simResult == null) {
      return AppErrorState(message: _error!, onRetry: _runSimulation);
    }

    final baseKpis = _simResult?['baseline_kpis'] ?? _simResult?['baseline'] ?? {};
    final simKpis = _simResult?['simulated_kpis'] ?? _simResult?['simulated'] ?? {};
    final deltas = _simResult?['deltas'] ?? {};
    final summary = _simResult?['summary_sentence'] ?? _simResult?['summary'] ?? '';
    final goalImpact = _simResult?['goal_impact'];
    final projections = (_simResult?['projections'] as List?) ?? (_simResult?['series'] as List?) ?? [];

    return SingleChildScrollView(
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
                    'Simulateur d\'Activité',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  Text(
                    'Modélisez l\'impact d\'une variation de volume ou de panier moyen sur votre chiffre d\'affaires',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Réinitialiser'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Control Sliders Card
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
                const Text(
                  'Paramètres de Simulation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                ),
                const SizedBox(height: 16),
                // Slider 1: Volume
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Variation du volume de transactions', style: TextStyle(fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _volumePct >= 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_volumePct >= 0 ? '+' : ''}${_volumePct.toStringAsFixed(0)} %',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _volumePct >= 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _volumePct,
                  min: -50,
                  max: 200,
                  divisions: 50,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() {
                      _volumePct = v;
                    });
                    _onParamsChanged();
                  },
                ),
                const SizedBox(height: 12),

                // Slider 2: Ticket moyen delta
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Variation du panier moyen (DZD)', style: TextStyle(fontWeight: FontWeight.w500)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _ticketDelta >= 0 ? AppColors.success.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_ticketDelta >= 0 ? '+' : ''}${_ticketDelta.toStringAsFixed(0)} DZD',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _ticketDelta >= 0 ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _ticketDelta,
                  min: -5000,
                  max: 10000,
                  divisions: 60,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    setState(() {
                      _ticketDelta = v;
                    });
                    _onParamsChanged();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Summary Sentence Banner
          if (summary.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insights, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      summary,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Actuel vs Simulé Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide
                  ? Row(
                      children: [
                        Expanded(child: _buildKpiCard('Actuel (30j)', baseKpis, false)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKpiCard('Simulé (Projection)', simKpis, true, deltas)),
                      ],
                    )
                  : Column(
                      children: [
                        _buildKpiCard('Actuel (30j)', baseKpis, false),
                        const SizedBox(height: 16),
                        _buildKpiCard('Simulé (Projection)', simKpis, true, deltas),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),

          // Goal impact section (if active)
          if (goalImpact != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, color: AppColors.cibBlue, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Impact sur l\'objectif mensuel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(
                          'Actuel : ${(goalImpact['baseline_attainment_pct'] as num?)?.toStringAsFixed(1) ?? 0}% '
                          '➔ Simulé : ${(goalImpact['simulated_attainment_pct'] as num?)?.toStringAsFixed(1) ?? 0}% de l\'objectif (${formatDzd(goalImpact['goal_amount'] ?? 0)})',
                          style: const TextStyle(fontSize: 13, color: AppColors.slate),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Projection Chart
          _buildProjectionChart(projections),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String title, Map kpis, bool isSimulated, [Map? deltas]) {
    final rev = (kpis['revenue'] as num?)?.toDouble() ?? 0.0;
    final cnt = (kpis['count'] as num?)?.toInt() ?? 0;
    final avg = (kpis['avg_ticket'] as num?)?.toDouble() ?? 0.0;

    final revDelta = (deltas?['revenue_delta'] as num?)?.toDouble();
    final revDeltaPct = (deltas?['revenue_delta_pct'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isSimulated ? const Color(0xFFF0FDF4) : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSimulated ? AppColors.success.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isSimulated ? AppColors.success : AppColors.slate)),
              if (isSimulated && revDeltaPct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: revDeltaPct >= 0 ? AppColors.success : AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    formatPct(revDeltaPct),
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(formatDzd(rev), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
          if (isSimulated && revDelta != null) ...[
            const SizedBox(height: 2),
            Text(
              '${revDelta >= 0 ? '+' : ''}${formatDzd(revDelta)} d\'écart',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: revDelta >= 0 ? AppColors.success : AppColors.danger),
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Volume tx', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text('$cnt tx', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Panier moyen', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(formatDzd(avg), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionChart(List projections) {
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
          const Text('Projection Temporelle (Actuel vs Simulé)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 4),
          const Text('Comparaison de la trajectoire d\'encaissement point par point', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: projections.isEmpty
                ? const Center(child: Text("Aucune projection disponible"))
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (val) => const FlLine(color: AppColors.border, strokeWidth: 1),
                      ),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        // Baseline
                        LineChartBarData(
                          spots: List.generate(projections.length, (i) {
                            final v = (projections[i]['baseline'] as num?)?.toDouble() ?? 0.0;
                            return FlSpot(i.toDouble(), v);
                          }),
                          isCurved: true,
                          color: AppColors.muted,
                          barWidth: 2,
                          dashArray: [4, 4],
                          dotData: const FlDotData(show: false),
                        ),
                        // Simulated
                        LineChartBarData(
                          spots: List.generate(projections.length, (i) {
                            final v = (projections[i]['simulated'] as num?)?.toDouble() ?? 0.0;
                            return FlSpot(i.toDouble(), v);
                          }),
                          isCurved: true,
                          color: AppColors.success,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 16, height: 2, color: AppColors.muted),
              const SizedBox(width: 6),
              const Text('Référence actuelle', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(width: 20),
              Container(width: 16, height: 3, color: AppColors.success),
              const SizedBox(width: 6),
              const Text('Projection simulée', style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
