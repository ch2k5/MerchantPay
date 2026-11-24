import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantTransactionsScreen extends ConsumerStatefulWidget {
  const MerchantTransactionsScreen({super.key});

  @override
  ConsumerState<MerchantTransactionsScreen> createState() => _MerchantTransactionsScreenState();
}

class _MerchantTransactionsScreenState extends ConsumerState<MerchantTransactionsScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedStatus;
  String? _selectedChannel;
  bool _isLoading = false;
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

  Future<void> _fetchTransactions({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = page;
    });

    try {
      final client = ref.read(apiClientProvider);
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': 15,
      };

      if (_searchCtrl.text.isNotEmpty) {
        queryParams['search'] = _searchCtrl.text.trim();
      }
      if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
        queryParams['status'] = _selectedStatus;
      }
      if (_selectedChannel != null && _selectedChannel!.isNotEmpty) {
        queryParams['channel'] = _selectedChannel;
      }

      final res = await client.get('/merchant/transactions/', queryParameters: queryParams);
      if (res.statusCode == 200) {
        setState(() {
          _transactions = res.data['results'] ?? [];
          _totalCount = res.data['count'] ?? 0;
          _totalPages = res.data['total_pages'] ?? 1;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Erreur lors du chargement des transactions.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _export(String format) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Génération de l'export $format en cours...")),
    );
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.dio.get<List<int>>(
        '/merchant/transactions/export/',
        queryParameters: {
          'format': format,
          if (_searchCtrl.text.isNotEmpty) 'search': _searchCtrl.text.trim(),
          if (_selectedStatus != null) 'status': _selectedStatus,
          if (_selectedChannel != null) 'channel': _selectedChannel,
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      if (res.statusCode == 200 && res.data != null && mounted) {
        final bytes = res.data!;
        final mimeType = format == 'pdf' ? 'application/pdf' : 'text/csv;charset=utf-8';
        final extension = format == 'pdf' ? 'pdf' : 'csv';
        final filename = 'releve_transactions.$extension';

        saveFile(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text("Export $format généré avec succès ! Téléchargement lancé ($filename)."),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text("Échec du téléchargement de l'export."),
          ),
        );
      }
    }
  }

  void _showDetailModal(Map<String, dynamic> tx) {
    final txStatus = tx['transaction_status'] ?? '';
    final isAccepted = txStatus == 'Accepted' || txStatus == 'ACCEPTED' || txStatus == 'COMPLETED';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(tx['reference'] ?? 'Détail de transaction', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modalRow("Montant", Formatters.formatDzd(tx['amount'])),
              _modalRow("Canal de paiement", tx['payment_channel'] ?? ''),
              _modalRow("Statut", tx['transaction_status'] ?? ''),
              _modalRow("Date & Heure", Formatters.formatDateTime(tx['transaction_date'])),
              _modalRow("Numéro de carte", "**** **** **** ${tx['card_last4'] ?? '****'}"),
              _modalRow("Identifiant Terminal", tx['terminal_id'] ?? '-'),
              if (tx['rejection_reason'] != null)
                _modalRow("Motif de rejet", tx['rejection_reason'], isAlert: true),
              if (tx['refunded_amount'] != null)
                _modalRow("Montant remboursé", Formatters.formatDzd(tx['refunded_amount'])),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
          if (isAccepted) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.undo, size: 15),
              label: const Text("Rembourser"),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.info),
              onPressed: () {
                Navigator.pop(ctx);
                _showRefundDialog(tx);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.block, size: 15),
              label: const Text("Décliner"),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () {
                Navigator.pop(ctx);
                _showDeclineConfirm(tx);
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showDeclineConfirm(Map<String, dynamic> tx) {
    final txId = tx['id'] ?? tx['transaction_id'] ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.block, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Décliner la transaction', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment décliner la transaction ${tx['reference'] ?? ''} d\'un montant de ${Formatters.formatDzd(tx['amount'])} ?\n\n'
          'Cette action est irréversible et ne peut être effectuée que sur des transactions acceptées.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await _declineTransaction(txId, tx['reference'] ?? '');
            },
            child: const Text('Confirmer la décision'),
          ),
        ],
      ),
    );
  }

  Future<void> _declineTransaction(String txId, String txRef) async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/merchant/transactions/$txId/decline/');
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.success, content: Text('Transaction $txRef déclinée avec succès.')),
        );
        _fetchTransactions(page: _currentPage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: AppColors.danger, content: Text('Impossible de décliner la transaction.')),
        );
      }
    }
  }

  void _showRefundDialog(Map<String, dynamic> tx) {
    final txId = tx['id'] ?? tx['transaction_id'] ?? '';
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.undo, color: AppColors.info),
            SizedBox(width: 8),
            Text('Rembourser la transaction', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Transaction : ${tx['reference'] ?? ''} — ${Formatters.formatDzd(tx['amount'])}'),
            const SizedBox(height: 16),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Montant à rembourser (DZD)',
                hintText: 'Ex: 5000',
                prefixIcon: Icon(Icons.money),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veuillez saisir un montant valide.')),
                );
                return;
              }
              Navigator.pop(ctx);
              await _refundTransaction(txId, amount, tx['reference'] ?? '');
            },
            child: const Text('Valider le remboursement'),
          ),
        ],
      ),
    );
  }

  Future<void> _refundTransaction(String txId, double amount, String txRef) async {
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post('/merchant/transactions/$txId/refund/', data: {'refund_amount': amount});
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.success, content: Text('Remboursement de ${Formatters.formatDzd(amount)} enregistré pour $ref.')),
        );
        _fetchTransactions(page: _currentPage);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: AppColors.danger, content: Text('Impossible d\'enregistrer le remboursement.')),
        );
      }
    }
  }

  Widget _modalRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.slate)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isAlert ? AppColors.danger : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title & Export
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Journal des Transactions", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text("$_totalCount transaction(s) enregistrée(s)", style: const TextStyle(fontSize: 13, color: AppColors.slate)),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _export('csv'),
                    icon: const Icon(Icons.table_view, size: 16),
                    label: const Text("Export CSV"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _export('pdf'),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text("Export PDF"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search & Filter Bar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Rechercher par référence, terminal, montant...',
                        prefixIcon: Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _fetchTransactions(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedStatus,
                    hint: const Text("Tous les statuts"),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: null, child: Text("Tous les statuts")),
                      DropdownMenuItem(value: "Accepted", child: Text("Accepted (Acceptée)")),
                      DropdownMenuItem(value: "Declined", child: Text("Declined (Refusée)")),
                      DropdownMenuItem(value: "Refunded", child: Text("Refunded (Remboursée)")),
                      DropdownMenuItem(value: "Cancelled", child: Text("Cancelled (Annulée)")),
                      DropdownMenuItem(value: "ACCEPTED", child: Text("Acceptée (CIB/EDAHABIA)")),
                      DropdownMenuItem(value: "REJECTED", child: Text("Rejetée")),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedStatus = v);
                      _fetchTransactions();
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _selectedChannel,
                    hint: const Text("Tous les canaux"),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: null, child: Text("Tous les canaux")),
                      DropdownMenuItem(value: "Contactless / NFC", child: Text("Contactless / NFC")),
                      DropdownMenuItem(value: "Mobile App", child: Text("Mobile App")),
                      DropdownMenuItem(value: "TPE / POS Terminal", child: Text("TPE / POS Terminal")),
                      DropdownMenuItem(value: "E-commerce (CIB / Edahabia)", child: Text("E-commerce")),
                      DropdownMenuItem(value: "Bank Transfer / Virement", child: Text("Bank Transfer / Virement")),
                      DropdownMenuItem(value: "CIB", child: Text("Carte CIB")),
                      DropdownMenuItem(value: "EDAHABIA", child: Text("Carte EDAHABIA")),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedChannel = v);
                      _fetchTransactions();
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off),
                    tooltip: "Réinitialiser les filtres",
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _selectedStatus = null;
                        _selectedChannel = null;
                      });
                      _fetchTransactions();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Transactions Table
          Expanded(
            child: Card(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? AppErrorState(message: _error!, onRetry: () => _fetchTransactions())
                      : _transactions.isEmpty
                          ? const AppEmptyState(
                              title: "Aucune transaction trouvée",
                              message: "Modifiez vos filtres ou effectuez une nouvelle recherche.",
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(AppColors.background),
                                        columns: const [
                                          DataColumn(label: Text('Référence', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Date & Heure', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Montant', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Canal', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Statut', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Motif rejet', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: _transactions.map((tx) {
                                          return DataRow(cells: [
                                            DataCell(Text(tx['reference'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                                            DataCell(Text(Formatters.formatDateTime(tx['transaction_date']))),
                                            DataCell(Text(Formatters.formatDzd(tx['amount']))),
                                            DataCell(Text(tx['payment_channel'] ?? '')),
                                            DataCell(_buildStatusBadge(tx['transaction_status'])),
                                            DataCell(Text(tx['rejection_reason'] ?? '-', style: const TextStyle(color: AppColors.slate, fontSize: 12))),
                                            DataCell(IconButton(
                                              icon: const Icon(Icons.visibility_outlined, size: 18),
                                              tooltip: "Voir le détail",
                                              onPressed: () => _showDetailModal(tx),
                                            )),
                                          ]);
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                                // Pagination Controls
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: const BoxDecoration(
                                    border: Border(top: BorderSide(color: AppColors.border)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "Page $_currentPage sur $_totalPages",
                                        style: const TextStyle(fontSize: 12, color: AppColors.slate),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.chevron_left),
                                            onPressed: _currentPage > 1
                                                ? () => _fetchTransactions(page: _currentPage - 1)
                                                : null,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.chevron_right),
                                            onPressed: _currentPage < _totalPages
                                                ? () => _fetchTransactions(page: _currentPage + 1)
                                                : null,
                                          ),
                                        ],
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
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color bg = AppColors.background;
    Color fg = AppColors.slate;
    String label = status ?? '';

    switch (status) {
      // Dataset values (capitalized)
      case 'Accepted':
      case 'ACCEPTED':
      case 'COMPLETED':
        bg = const Color(0xFFE8F5E9);
        fg = AppColors.success;
        label = 'Acceptée';
        break;
      case 'Declined':
      case 'REJECTED':
      case 'DECLINED':
        bg = const Color(0xFFFFEBEE);
        fg = AppColors.danger;
        label = 'Refusée';
        break;
      case 'Cancelled':
      case 'CANCELLED':
        bg = const Color(0xFFFFF3E0);
        fg = AppColors.warning;
        label = 'Annulée';
        break;
      case 'Refunded':
      case 'REFUNDED':
        bg = const Color(0xFFE1F5FE);
        fg = AppColors.info;
        label = 'Remboursée';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
