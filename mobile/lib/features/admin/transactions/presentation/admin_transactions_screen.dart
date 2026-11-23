import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';

class AdminTransactionsScreen extends ConsumerStatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  ConsumerState<AdminTransactionsScreen> createState() => _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends ConsumerState<AdminTransactionsScreen> {
  final _searchController = TextEditingController();
  String _selectedStatus = 'ALL';
  String _selectedChannel = 'ALL';
  bool _isLoading = true;
  String? _error;
  List<dynamic> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
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
      if (_selectedChannel != 'ALL') {
        query['channel'] = _selectedChannel;
      }
      final res = await client.get('/admin/transactions/', queryParameters: query);
      if (res.statusCode == 200) {
        setState(() {
          _transactions = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer les transactions du réseau.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportCsv() async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/admin/transactions/export/', queryParameters: {'format': 'csv'});
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Export CSV global généré avec succès.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'export CSV.")),
        );
      }
    }
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
                  Text('Explorateur Global des Transactions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Registre consolidé de toutes les opérations CIB & EDAHABIA sur le réseau', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Exporter CSV'),
                  ),
                  FilledButton.icon(
                    onPressed: _fetchTransactions,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualiser'),
                  ),
                ],
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
                      hintText: 'Rechercher par référence, commerçant, code...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetchTransactions(),
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedChannel,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tous réseaux')),
                    DropdownMenuItem(value: 'CIB', child: Text('CIB')),
                    DropdownMenuItem(value: 'EDAHABIA', child: Text('EDAHABIA')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedChannel = v;
                      });
                      _fetchTransactions();
                    }
                  },
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tous statuts')),
                    DropdownMenuItem(value: 'COMPLETED', child: Text('Validées')),
                    DropdownMenuItem(value: 'REJECTED', child: Text('Rejetées')),
                    DropdownMenuItem(value: 'PENDING', child: Text('En attente')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _selectedStatus = v;
                      });
                      _fetchTransactions();
                    }
                  },
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _fetchTransactions,
                  child: const Text('Filtrer'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Transactions Table Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _fetchTransactions)
                    : _transactions.isEmpty
                        ? const AppEmptyState(title: "Aucune transaction trouvée", message: "Modifiez vos filtres de recherche.")
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date & Heure')),
                                DataColumn(label: Text('Référence')),
                                DataColumn(label: Text('Commerçant')),
                                DataColumn(label: Text('Carte')),
                                DataColumn(label: Text('Montant (DZD)')),
                                DataColumn(label: Text('Statut')),
                              ],
                              rows: _transactions.map((tx) {
                                final isCib = tx['channel'] == 'CIB';
                                final isSuccess = tx['status'] == 'COMPLETED';
                                final isRejected = tx['status'] == 'REJECTED';

                                return DataRow(
                                  cells: [
                                    DataCell(Text(formatDateTime(tx['timestamp']), style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(tx['reference'] ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                                    DataCell(Text(tx['merchant_name'] ?? 'Commerçant #${tx['merchant']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isCib ? AppColors.cibBlue.withValues(alpha: 0.1) : AppColors.edahabiaGold.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tx['channel_display'] ?? tx['channel'],
                                          style: TextStyle(
                                            color: isCib ? AppColors.cibBlue : const Color(0xFFB45309),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        formatDzd(tx['amount']),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isSuccess
                                              ? AppColors.success.withValues(alpha: 0.1)
                                              : isRejected
                                                  ? AppColors.danger.withValues(alpha: 0.1)
                                                  : AppColors.warning.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          tx['status_display'] ?? tx['status'],
                                          style: TextStyle(
                                            color: isSuccess
                                                ? AppColors.success
                                                : isRejected
                                                    ? AppColors.danger
                                                    : AppColors.warning,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
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
