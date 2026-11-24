import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantAlertsScreen extends ConsumerStatefulWidget {
  const MerchantAlertsScreen({super.key});

  @override
  ConsumerState<MerchantAlertsScreen> createState() => _MerchantAlertsScreenState();
}

class _MerchantAlertsScreenState extends ConsumerState<MerchantAlertsScreen> {
  String _selectedSeverity = 'ALL';
  bool _isLoading = true;
  bool _isEvaluating = false;
  String? _error;
  List<dynamic> _alerts = [];

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{};
      if (_selectedSeverity != 'ALL') {
        query['severity'] = _selectedSeverity;
      }
      final res = await client.get('/merchant/alerts/', queryParameters: query);
      if (res.statusCode == 200) {
        setState(() {
          _alerts = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer vos alertes.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(dynamic id) async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/merchant/alerts/$id/read/');
      if (res.statusCode == 200) {
        setState(() {
          final idx = _alerts.indexWhere((a) => a['id'] == id);
          if (idx != -1) {
            _alerts[idx]['status'] = 'READ';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec du marquage de l'alerte.")),
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/merchant/alerts/read-all/');
      if (res.statusCode == 200) {
        setState(() {
          for (var a in _alerts) {
            a['status'] = 'READ';
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Toutes les alertes ont été marquées comme lues.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de la mise à jour.")),
        );
      }
    }
  }

  Future<void> _evaluateRules() async {
    setState(() {
      _isEvaluating = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/merchant/alerts/evaluate/');
      if (res.statusCode == 200) {
        final count = res.data['alerts_created'] ?? 0;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(count > 0 ? '$count nouvelle(s) alerte(s) détectée(s).' : 'Toutes les alertes sont à jour.')),
          );
        }
        await _fetchAlerts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'évaluation des règles.")),
        );
      }
    } finally {
      setState(() {
        _isEvaluating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _alerts.where((a) => a['status'] == 'NEW').length;

    return RefreshIndicator(
      onRefresh: _fetchAlerts,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Alertes & Recommandations',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unreadCount non lue${unreadCount > 1 ? 's' : ''}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Text(
                      'Détection automatique de variations, anomalies et opportunités de croissance',
                      style: TextStyle(fontSize: 13, color: AppColors.muted),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isEvaluating ? null : _evaluateRules,
                      icon: _isEvaluating
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16),
                      label: const Text('Actualiser les règles'),
                    ),
                    if (unreadCount > 0)
                      FilledButton.tonalIcon(
                        onPressed: _markAllAsRead,
                        icon: const Icon(Icons.done_all, size: 16),
                        label: const Text('Tout marquer comme lu'),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Severity Filter
            Row(
              children: [
                _buildFilterChip('ALL', 'Toutes (${_alerts.length})'),
                const SizedBox(width: 8),
                _buildFilterChip('CRITICAL', 'Critiques'),
                const SizedBox(width: 8),
                _buildFilterChip('WARNING', 'Avertissements'),
                const SizedBox(width: 8),
                _buildFilterChip('INFO', 'Informatif'),
                const SizedBox(width: 8),
                _buildFilterChip('SUCCESS', 'Objectifs'),
              ],
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (_error != null)
              AppErrorState(message: _error!, onRetry: _fetchAlerts)
            else if (_alerts.isEmpty)
              const AppEmptyState(
                title: "Aucune alerte active",
                message: "Toutes vos métriques d'encaissement fonctionnent normalement.",
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alerts.length,
                separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _buildAlertCard(_alerts[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String severity, String label) {
    final isSelected = _selectedSeverity == severity;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedSeverity = severity;
          });
          _fetchAlerts();
        }
      },
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final severity = alert['severity'] ?? 'INFO';
    final alertType = alert['type'] ?? '';
    final isAdminObs = alertType == 'ADMIN_OBSERVATION';
    final isNew = alert['status'] == 'NEW';
    final snapshot = alert['metric_snapshot'] as Map<String, dynamic>?;

    Color badgeColor;
    IconData badgeIcon;

    if (isAdminObs) {
      badgeColor = const Color(0xFF1565C0); // Deep blue for SATIM messages
      badgeIcon = Icons.shield_outlined;
    } else {
      switch (severity) {
        case 'CRITICAL':
          badgeColor = AppColors.danger;
          badgeIcon = Icons.error_outline;
          break;
        case 'WARNING':
          badgeColor = AppColors.warning;
          badgeIcon = Icons.warning_amber_outlined;
          break;
        case 'SUCCESS':
          badgeColor = AppColors.success;
          badgeIcon = Icons.check_circle_outline;
          break;
        default:
          badgeColor = AppColors.cibBlue;
          badgeIcon = Icons.info_outline;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isNew ? badgeColor.withValues(alpha: 0.03) : AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNew ? badgeColor.withValues(alpha: 0.4) : AppColors.border,
          width: isNew ? 1.5 : 1.0,
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(badgeIcon, color: badgeColor, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                alert['title'] ?? 'Alerte',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isNew ? FontWeight.bold : FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (isNew)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                child: const Text('NOUVEAU', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            if (isAdminObs)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF1565C0), borderRadius: BorderRadius.circular(4)),
                child: const Text('SATIM', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
            Text(
              formatDateTime(alert['created_at']),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Text(
            alert['message'] ?? '',
            style: const TextStyle(fontSize: 13, color: AppColors.slate),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                // Recommendation
                if (alert['recommendation'] != null && alert['recommendation'].toString().isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: AppColors.edahabiaGold, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Action recommandée :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(alert['recommendation'], style: const TextStyle(fontSize: 13, color: AppColors.ink)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Metric snapshot explanation
                if (snapshot != null && snapshot.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pourquoi cette alerte ? (Données au déclenchement)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          children: snapshot.entries.map((e) {
                            return Text(
                              '${e.key} : ${e.value}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.ink),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isNew)
                      TextButton.icon(
                        onPressed: () => _markAsRead(alert['id']),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Marquer comme lu'),
                      ),
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
