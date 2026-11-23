import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/widgets/risk_gauge.dart';

class AdminRiskScreen extends ConsumerStatefulWidget {
  const AdminRiskScreen({super.key});

  @override
  ConsumerState<AdminRiskScreen> createState() => _AdminRiskScreenState();
}

class _AdminRiskScreenState extends ConsumerState<AdminRiskScreen> {
  String _selectedStatus = 'ALL';
  bool _isLoading = true;
  String? _error;
  List<dynamic> _riskFlags = [];

  @override
  void initState() {
    super.initState();
    _fetchRiskFlags();
  }

  Future<void> _fetchRiskFlags() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{};
      if (_selectedStatus != 'ALL') {
        query['status'] = _selectedStatus;
      }
      final res = await client.get('/admin/risk/', queryParameters: query);
      if (res.statusCode == 200) {
        setState(() {
          _riskFlags = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer les dossiers de risque.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _openInvestigation(Map<String, dynamic> flag) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InvestigationDialog(
        flag: flag,
        onUpdated: () {
          _fetchRiskFlags();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  Text('Surveillance du Risque & Anti-Fraude', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Moteur de détection heuristique et explicable des comportements suspects', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
              FilledButton.icon(
                onPressed: _fetchRiskFlags,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Legal Disclaimer Banner (MANDATORY)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: AppColors.warning, size: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Avertissement légal & Déontologie SATIM',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.ink),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'La détection automatisée du risque constitue une aide à la décision purement indicative. '
                        'Elle ne saurait se substituer à une enquête humaine approfondie ni entraîner de sanction automatique '
                        'sans validation préalable par un analyste SATIM habilité.',
                        style: TextStyle(fontSize: 12, color: AppColors.slate),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Filter tabs
          Row(
            children: [
              _buildFilterChip('ALL', 'Tous les dossiers (${_riskFlags.length})'),
              const SizedBox(width: 8),
              _buildFilterChip('NEW', 'Nouveaux'),
              const SizedBox(width: 8),
              _buildFilterChip('UNDER_REVIEW', 'En cours d\'instruction'),
              const SizedBox(width: 8),
              _buildFilterChip('CONFIRMED', 'Confirmés'),
              const SizedBox(width: 8),
              _buildFilterChip('DISMISSED', 'Classés sans suite'),
            ],
          ),
          const SizedBox(height: 20),

          // Risk Flags List
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          else if (_error != null)
            AppErrorState(message: _error!, onRetry: _fetchRiskFlags)
          else if (_riskFlags.isEmpty)
            const AppEmptyState(
              title: "Aucune alerte de risque",
              message: "Aucun comportement anormal n'a été détecté selon les critères actuels.",
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _riskFlags.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => _buildRiskCard(_riskFlags[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _selectedStatus == status;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (val) {
        if (val) {
          setState(() {
            _selectedStatus = status;
          });
          _fetchRiskFlags();
        }
      },
    );
  }

  Widget _buildRiskCard(Map<String, dynamic> flag) {
    final score = (flag['score'] as num?)?.toInt() ?? 0;
    final status = flag['status'] ?? 'NEW';
    final triggeredRules = (flag['triggered_rules'] as List?) ?? [];

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'UNDER_REVIEW':
        statusColor = AppColors.cibBlue;
        statusLabel = 'En instruction';
        break;
      case 'CONFIRMED':
        statusColor = AppColors.danger;
        statusLabel = 'Fraude confirmée';
        break;
      case 'DISMISSED':
        statusColor = AppColors.muted;
        statusLabel = 'Classé sans suite';
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'Nouveau signalement';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: score >= 70 ? AppColors.danger.withValues(alpha: 0.3) : AppColors.border,
          width: score >= 70 ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RiskGauge(score: score, size: 70),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          flag['merchant_name'] ?? 'Commerçant inconnu',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Détecté le ${formatDateTime(flag['created_at'])} • Fenêtre d\'analyse : ${flag['window_minutes'] ?? 60} min',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                    const SizedBox(height: 10),
                    // Triggered rules badges
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: triggeredRules.map((r) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${r['rule_name'] ?? r['rule_code']} (+${r['score_delta']})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(flag['notes'] as List?)?.length ?? 0} note(s) d\'analyste',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openInvestigation(flag),
                icon: const Icon(Icons.manage_search, size: 16),
                label: const Text('Instruire le dossier'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvestigationDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> flag;
  final VoidCallback onUpdated;

  const _InvestigationDialog({required this.flag, required this.onUpdated});

  @override
  ConsumerState<_InvestigationDialog> createState() => _InvestigationDialogState();
}

class _InvestigationDialogState extends ConsumerState<_InvestigationDialog> {
  late String _status;
  final _noteController = TextEditingController();
  bool _isSaving = false;
  List<dynamic> _notes = [];

  @override
  void initState() {
    super.initState();
    _status = widget.flag['status'] ?? 'NEW';
    _notes = List.from((widget.flag['notes'] as List?) ?? []);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final flagId = widget.flag['id'];
      final res = await client.post(
        '/admin/risk/$flagId/status/',
        data: {
          'status': _status,
          if (_noteController.text.trim().isNotEmpty) 'note': _noteController.text.trim(),
        },
      );
      if (res.statusCode == 200) {
        widget.onUpdated();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Dossier de risque mis à jour.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de la mise à jour.")),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _addNote() async {
    final noteText = _noteController.text.trim();
    if (noteText.isEmpty) return;

    try {
      final client = ref.read(apiClientProvider);
      final flagId = widget.flag['id'];
      final res = await client.post(
        '/admin/risk/$flagId/notes/',
        data: {'note': noteText},
      );
      if (res.statusCode == 201) {
        setState(() {
          _notes.insert(0, res.data);
          _noteController.clear();
        });
        widget.onUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ajouter la note.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = (widget.flag['score'] as num?)?.toInt() ?? 0;
    final rules = (widget.flag['triggered_rules'] as List?) ?? [];
    final snapshot = widget.flag['metric_snapshot'] as Map<String, dynamic>?;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      RiskGauge(score: score, size: 48),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.flag['merchant_name'] ?? 'Commerçant', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Dossier #${widget.flag['id']} • Score $score / 100', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(height: 24),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Triggered rules detail
                      const Text('Règles de Détection Déclenchées', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...rules.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(4)),
                                child: Text('+${r['score_delta']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r['rule_name'] ?? r['rule_code'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (r['description'] != null) Text(r['description'], style: const TextStyle(fontSize: 12, color: AppColors.slate)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),

                      // Metric snapshot
                      if (snapshot != null && snapshot.isNotEmpty) ...[
                        const Text('Métriques au Moment de la Détection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: snapshot.entries.map((e) => Text('${e.key} = ${e.value}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Status selection
                      const Text('Décision & Statut d\'Instruction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'NEW', child: Text('Nouveau signalement')),
                          DropdownMenuItem(value: 'UNDER_REVIEW', child: Text('En cours d\'instruction par SATIM')),
                          DropdownMenuItem(value: 'CONFIRMED', child: Text('Fraude avérée / Blocage préventif')),
                          DropdownMenuItem(value: 'DISMISSED', child: Text('Faux positif / Dossier classé sans suite')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _status = v);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Add note
                      const Text('Ajouter une Note d\'Investigation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                hintText: 'Observation, justificatif ou conclusion...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _addNote,
                            icon: const Icon(Icons.send, color: AppColors.primary),
                            tooltip: 'Ajouter la note',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Notes thread
                      if (_notes.isNotEmpty) ...[
                        const Text('Historique des Notes d\'Analystes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate)),
                        const SizedBox(height: 8),
                        ..._notes.map((n) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(n['author_name'] ?? n['author_email'] ?? 'Analyste', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    Text(formatDateTime(n['created_at']), style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(n['note'] ?? '', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // Dialog Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _updateStatus,
                    icon: _isSaving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
                    label: const Text('Enregistrer la décision'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
