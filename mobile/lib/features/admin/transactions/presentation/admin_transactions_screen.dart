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
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;

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

  Future<void> _fetchTransactions({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = page;
    });
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{
        'page': page,
        'page_size': 20,
      };
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
        if (res.data is Map) {
          setState(() {
            _transactions = res.data['results'] ?? [];
            _totalCount = res.data['count'] ?? _transactions.length;
            _totalPages = res.data['total_pages'] ?? ((_totalCount / 20).ceil()).clamp(1, 9999);
          });
        } else if (res.data is List) {
          setState(() {
            _transactions = res.data;
            _totalCount = _transactions.length;
            _totalPages = 1;
          });
        }
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

  Future<void> _export(String format) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Génération de l'export $format en cours...")),
    );
    try {
      final client = ref.read(apiClientProvider);
      final query = <String, dynamic>{'format': format};
      if (_searchController.text.isNotEmpty) {
        query['search'] = _searchController.text.trim();
      }
      if (_selectedStatus != 'ALL') {
        query['status'] = _selectedStatus;
      }
      if (_selectedChannel != 'ALL') {
        query['channel'] = _selectedChannel;
      }
      final res = await client.get('/admin/transactions/export/', queryParameters: query);
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text("Export $format téléchargé avec succès !"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text("Échec de l'export $format."),
          ),
        );
      }
    }
  }

  void _showDetailModal(Map<String, dynamic> tx) {
    final statusStr = tx['status_display'] ?? tx['status'] ?? tx['transaction_status'] ?? '-';
    final isAccepted = statusStr == 'Accepted' || statusStr == 'COMPLETED' || statusStr == 'Acceptée';
    final isDeclined = statusStr == 'Declined' || statusStr == 'REJECTED' || statusStr == 'Refusée';
    final channelStr = tx['channel_display'] ?? tx['channel'] ?? tx['payment_channel'] ?? '-';
    final merchantInfo = tx['merchant_details'] as Map? ?? {};
    final merchantName = tx['merchant_name'] ?? merchantInfo['business_name'] ?? 'Commerçant';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tx['reference'] ?? 'Détail de transaction',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _modalRow("Montant", formatDzd(tx['amount'] ?? 0)),
                _modalRow("Commerçant", '$merchantName (${merchantInfo['merchant_code'] ?? tx['merchant']})'),
                if (merchantInfo['wilaya'] != null)
                  _modalRow("Wilaya", merchantInfo['wilaya'].toString()),
                if (tx['merchant_category'] != null)
                  _modalRow("Catégorie d'activité", tx['merchant_category'].toString()),
                _modalRow("Canal de paiement", channelStr),
                _modalRow(
                  "Statut",
                  statusStr,
                  valueColor: isAccepted ? AppColors.success : (isDeclined ? AppColors.danger : AppColors.warning),
                ),
                _modalRow("Date & Heure", formatDateTime(tx['timestamp'] ?? tx['transaction_date'])),
                _modalRow("Numéro de carte", "**** **** **** ${tx['card_last4'] ?? '****'}"),
                _modalRow("Identifiant Terminal", tx['terminal_id'] ?? '-'),
                if (tx['rejection_reason'] != null && tx['rejection_reason'].toString().isNotEmpty)
                  _modalRow("Motif de rejet", tx['rejection_reason'].toString(), isAlert: true),
                if (tx['refunded_amount'] != null && (tx['refunded_amount'] as num) > 0)
                  _modalRow("Montant remboursé", formatDzd(tx['refunded_amount'])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
        ],
      ),
    );
  }

  Widget _modalRow(String label, String value, {bool isAlert = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isAlert ? AppColors.danger : (valueColor ?? AppColors.ink),
              ),
            ),
          ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Explorateur Global des Transactions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text(
                    '$_totalCount opération(s) enregistrée(s) sur le réseau SATIM CIB & EDAHABIA',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted),
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
                    label: const Text('Export PDF'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _fetchTransactions(page: _currentPage),
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
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Réf, commerçant, terminal, carte...',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _fetchTransactions(page: 1),
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedChannel,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tous canaux')),
                    DropdownMenuItem(value: 'Contactless / NFC', child: Text('Contactless / NFC')),
                    DropdownMenuItem(value: 'Mobile App', child: Text('Mobile App')),
                    DropdownMenuItem(value: 'TPE / POS Terminal', child: Text('TPE / POS Terminal')),
                    DropdownMenuItem(value: 'E-commerce (CIB / Edahabia)', child: Text('E-commerce')),
                    DropdownMenuItem(value: 'Bank Transfer / Virement', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'CIB', child: Text('CIB')),
                    DropdownMenuItem(value: 'EDAHABIA', child: Text('EDAHABIA')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedChannel = v);
                      _fetchTransactions(page: 1);
                    }
                  },
                ),
                DropdownButton<String>(
                  value: _selectedStatus,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tous statuts')),
                    DropdownMenuItem(value: 'Accepted', child: Text('Accepted (Acceptées)')),
                    DropdownMenuItem(value: 'Declined', child: Text('Declined (Refusées)')),
                    DropdownMenuItem(value: 'Refunded', child: Text('Refunded (Remboursées)')),
                    DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled (Annulées)')),
                    DropdownMenuItem(value: 'COMPLETED', child: Text('Validées (Legacy)')),
                    DropdownMenuItem(value: 'REJECTED', child: Text('Rejetées (Legacy)')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedStatus = v);
                      _fetchTransactions(page: 1);
                    }
                  },
                ),
                FilledButton(
                  onPressed: () => _fetchTransactions(page: 1),
                  child: const Text('Filtrer'),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_alt_off),
                  tooltip: 'Réinitialiser',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _selectedChannel = 'ALL';
                      _selectedStatus = 'ALL';
                    });
                    _fetchTransactions(page: 1);
                  },
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
                    ? AppErrorState(message: _error!, onRetry: () => _fetchTransactions(page: _currentPage))
                    : _transactions.isEmpty
                        ? const AppEmptyState(title: "Aucune transaction trouvée", message: "Modifiez vos filtres de recherche.")
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  showCheckboxColumn: false,
                                  columns: const [
                                    DataColumn(label: Text('Date & Heure')),
                                    DataColumn(label: Text('Référence')),
                                    DataColumn(label: Text('Commerçant')),
                                    DataColumn(label: Text('Canal / Carte')),
                                    DataColumn(label: Text('Montant (DZD)')),
                                    DataColumn(label: Text('Statut')),
                                    DataColumn(label: Text('Action')),
                                  ],
                                  rows: _transactions.map((tx) {
                                    final statusStr = tx['status_display'] ?? tx['status'] ?? tx['transaction_status'] ?? '-';
                                    final isAccepted = statusStr == 'Accepted' || statusStr == 'COMPLETED' || statusStr == 'Acceptée';
                                    final isDeclined = statusStr == 'Declined' || statusStr == 'REJECTED' || statusStr == 'Refusée';
                                    final channelStr = tx['channel_display'] ?? tx['channel'] ?? tx['payment_channel'] ?? '-';
                                    final merchantInfo = tx['merchant_details'] as Map? ?? {};
                                    final merchantName = tx['merchant_name'] ?? merchantInfo['business_name'] ?? 'Commerçant';

                                    return DataRow(
                                      onSelectChanged: (_) => _showDetailModal(Map<String, dynamic>.from(tx)),
                                      cells: [
                                        DataCell(Text(formatDateTime(tx['timestamp'] ?? tx['transaction_date']), style: const TextStyle(fontSize: 12))),
                                        DataCell(Text(tx['reference'] ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600))),
                                        DataCell(Text(merchantName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              channelStr,
                                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            formatDzd(tx['amount'] ?? 0),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: isAccepted
                                                  ? AppColors.success.withValues(alpha: 0.1)
                                                  : isDeclined
                                                      ? AppColors.danger.withValues(alpha: 0.1)
                                                      : AppColors.warning.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              statusStr,
                                              style: TextStyle(
                                                color: isAccepted
                                                    ? AppColors.success
                                                    : isDeclined
                                                        ? AppColors.danger
                                                        : AppColors.warning,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          IconButton(
                                            icon: const Icon(Icons.visibility_outlined, size: 18),
                                            tooltip: 'Détails',
                                            onPressed: () => _showDetailModal(Map<String, dynamic>.from(tx)),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),

                              // Pagination Controls
                              if (_totalPages > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: AppColors.border)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Page $_currentPage sur $_totalPages (${_transactions.length} affichées)',
                                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                      ),
                                      Row(
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _currentPage > 1 ? () => _fetchTransactions(page: _currentPage - 1) : null,
                                            icon: const Icon(Icons.chevron_left, size: 18),
                                            label: const Text('Précédent'),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: _currentPage < _totalPages ? () => _fetchTransactions(page: _currentPage + 1) : null,
                                            icon: const Icon(Icons.chevron_right, size: 18),
                                            label: const Text('Suivant'),
                                          ),
                                        ],
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
}
