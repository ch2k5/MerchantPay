import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';

class AdminMerchantsScreen extends ConsumerStatefulWidget {
  const AdminMerchantsScreen({super.key});

  @override
  ConsumerState<AdminMerchantsScreen> createState() => _AdminMerchantsScreenState();
}

class _AdminMerchantsScreenState extends ConsumerState<AdminMerchantsScreen> {
  final _searchController = TextEditingController();
  String _selectedStatus = 'ALL';
  bool _isLoading = true;
  String? _error;
  List<dynamic> _merchants = [];

  @override
  void initState() {
    super.initState();
    _fetchMerchants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMerchants() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{};
      if (_searchController.text.isNotEmpty) {
        query['search'] = _searchController.text.trim();
      }
      if (_selectedStatus != 'ALL') {
        query['status'] = _selectedStatus;
      }
      final res = await client.get('/admin/merchants/', queryParameters: query);
      if (res.statusCode == 200) {
        setState(() {
          _merchants = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer la liste des commerçants.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleMerchantActive(Map<String, dynamic> merchant) async {
    final authState = ref.read(authStateProvider);
    if (!authState.isSuperAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Seul un Administrateur Principal (SUPER_ADMIN) peut activer/désactiver un commerçant.")),
      );
      return;
    }

    final reasonController = TextEditingController();
    final isCurrentlyActive = merchant['status'] == 'ACTIVE';
    final actionName = isCurrentlyActive ? 'Désactiver' : 'Activer';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$actionName le commerçant ${merchant['business_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Voulez-vous vraiment $actionName ce compte commerçant ?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motif obligatoire',
                hintText: 'Ex: Demande légale, suspicion de fraude...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: isCurrentlyActive ? AppColors.danger : AppColors.success),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Le motif est requis.")));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(actionName),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final client = ref.read(apiClientProvider);
        final res = await client.post(
          '/admin/merchants/${merchant['id']}/toggle-active/',
          data: {'reason': reasonController.text.trim()},
        );
        if (res.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Statut du commerçant mis à jour avec succès.")),
            );
          }
          await _fetchMerchants();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Erreur lors de la modification du statut.")),
          );
        }
      }
    }
  }

  void _showMerchantDetail(Map<String, dynamic> merchant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      merchant['business_name'] ?? 'Commerçant',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: merchant['status'] == 'ACTIVE' ? AppColors.success.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      merchant['status'] == 'ACTIVE' ? 'Actif' : 'Désactivé',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: merchant['status'] == 'ACTIVE' ? AppColors.success : AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDetailRow('Identifiant (ID)', '${merchant['id']}'),
              _buildDetailRow('N° Enregistrement (RC/NIF)', merchant['legal_id'] ?? '-'),
              _buildDetailRow('Contact principal', merchant['contact_name'] ?? '-'),
              _buildDetailRow('Téléphone', merchant['phone'] ?? '-'),
              _buildDetailRow('Localisation', '${merchant['commune'] ?? '-'}, ${merchant['wilaya'] ?? '-'}'),
              _buildDetailRow('Secteur MCC', '${merchant['mcc_display'] ?? merchant['mcc'] ?? '-'}'),
              _buildDetailRow('Objectif Mensuel', formatDzd(merchant['monthly_goal'] ?? 0)),
              _buildDetailRow('Date d\'adhésion', formatDate(merchant['created_at'])),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fermer'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _toggleMerchantActive(merchant);
                    },
                    child: Text(merchant['status'] == 'ACTIVE' ? 'Désactiver le compte' : 'Activer le compte'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 180, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
        ],
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
                  Text('Gestion des Commerçants', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Registre national des commerçants connectés au réseau SATIM', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
              FilledButton.icon(
                onPressed: _fetchMerchants,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Rechercher par raison sociale, NIF, contact...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetchMerchants(),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tous les statuts')),
                    DropdownMenuItem(value: 'ACTIVE', child: Text('Actifs')),
                    DropdownMenuItem(value: 'INACTIVE', child: Text('Désactivés')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedStatus = v;
                      });
                      _fetchMerchants();
                    }
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _fetchMerchants,
                  child: const Text('Filtrer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Merchants Table Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _fetchMerchants)
                    : _merchants.isEmpty
                        ? const AppEmptyState(title: "Aucun commerçant trouvé", message: "Modifiez vos filtres de recherche.")
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Raison Sociale')),
                                DataColumn(label: Text('Secteur MCC')),
                                DataColumn(label: Text('Wilaya')),
                                DataColumn(label: Text('Contact')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _merchants.map((m) {
                                final isActive = m['status'] == 'ACTIVE';
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(m['business_name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text(m['legal_id'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text(m['mcc_display'] ?? m['mcc'] ?? '-', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(m['wilaya'] ?? '-', style: const TextStyle(fontSize: 12))),
                                    DataCell(
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(m['contact_name'] ?? '-', style: const TextStyle(fontSize: 12)),
                                          Text(m['phone'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          isActive ? 'Actif' : 'Désactivé',
                                          style: TextStyle(
                                            color: isActive ? AppColors.success : AppColors.danger,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.visibility, size: 18, color: AppColors.cibBlue),
                                            tooltip: 'Détails du commerçant',
                                            onPressed: () => _showMerchantDetail(m),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              isActive ? Icons.block : Icons.check_circle_outline,
                                              size: 18,
                                              color: isActive ? AppColors.danger : AppColors.success,
                                            ),
                                            tooltip: isActive ? 'Désactiver' : 'Activer',
                                            onPressed: () => _toggleMerchantActive(m),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
