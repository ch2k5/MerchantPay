import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';

class AdminAuditScreen extends ConsumerStatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  ConsumerState<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends ConsumerState<AdminAuditScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
  }

  Future<void> _fetchAuditLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/admin/audit/');
      if (res.statusCode == 200) {
        setState(() {
          _logs = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer les journaux d'audit.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                  Text('Journal d\'Audit & Traçabilité (SUPER_ADMIN)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Registre infalsifiable de toutes les actions administratives sensibles', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
              FilledButton.icon(
                onPressed: _fetchAuditLogs,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Logs Table
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _fetchAuditLogs)
                    : _logs.isEmpty
                        ? const AppEmptyState(title: "Aucun log d'audit", message: "Toutes les opérations sensibles apparaîtront ici.")
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date & Heure')),
                                DataColumn(label: Text('Auteur')),
                                DataColumn(label: Text('Action')),
                                DataColumn(label: Text('Cible')),
                                DataColumn(label: Text('Adresse IP')),
                              ],
                              rows: _logs.map((log) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(formatDateTime(log['timestamp']), style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(log['actor_email'] ?? 'Système', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(log['action_display'] ?? log['action'] ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                    DataCell(Text(log['target'] ?? '-', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(log['ip_address'] ?? '127.0.0.1', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.muted))),
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
