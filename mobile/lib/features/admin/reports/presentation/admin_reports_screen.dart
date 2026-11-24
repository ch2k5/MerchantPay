import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/file_saver.dart';

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  String _selectedReport = 'MONTHLY_VOLUME';
  String _selectedFormat = 'pdf';
  String _selectedPreset = 'all';
  bool _isGenerating = false;

  final reports = [
    {
      'code': 'MONTHLY_VOLUME',
      'title': 'Rapport Mensuel des Volumes & Flux',
      'description': 'Synthèse consolidée des encaissements par wilaya, secteur MCC et réseau (CIB vs EDAHABIA).',
      'icon': Icons.pie_chart_outline,
    },
    {
      'code': 'RISK_AUDIT',
      'title': 'Audit de Sécurité & Détections Fraude',
      'description': 'Rapport des scores de risque, alertes déclenchées et état des dossiers d\'investigation.',
      'icon': Icons.security,
    },
    {
      'code': 'MERCHANT_ACTIVITY',
      'title': 'Bilan d\'Activité du Réseau Commerçants',
      'description': 'Liste des commerçants actifs, taux de rejet par terminal, nouvelles adhésions et suspensions.',
      'icon': Icons.storefront,
    },
  ];

  Future<void> _generateReport() async {
    setState(() {
      _isGenerating = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.dio.get<List<int>>(
        '/admin/reports/generate/',
        queryParameters: {
          'report_type': _selectedReport,
          'format': _selectedFormat,
          'preset': _selectedPreset,
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      if (res.statusCode == 200 && res.data != null && mounted) {
        final bytes = res.data!;
        final mimeType = _selectedFormat == 'pdf' ? 'application/pdf' : 'text/csv;charset=utf-8';
        final extension = _selectedFormat == 'pdf' ? 'pdf' : 'csv';
        final filename = 'rapport_satim_${_selectedReport.toLowerCase()}.$extension';

        saveFile(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              "Rapport ${_selectedFormat.toUpperCase()} généré avec succès ! Téléchargement lancé ($filename).",
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.danger,
            content: Text("Échec du téléchargement du rapport."),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            content: Text("Erreur lors de la génération du rapport : $e"),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
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
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rapports Réglementaires & Décisionnels', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
              Text('Génération de rapports institutionnels SATIM au format PDF certifié ou export brut CSV', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 24),

          // Report Types Selector
          ...reports.map((r) {
            final isSelected = _selectedReport == r['code'];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withValues(alpha: 0.04) : AppColors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected ? AppColors.primary : const Color(0xFFF1F5F9),
                  child: Icon(r['icon'] as IconData, color: isSelected ? Colors.white : AppColors.slate, size: 20),
                ),
                title: Text(r['title'] as String, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? AppColors.primary : AppColors.ink)),
                subtitle: Text(r['description'] as String, style: const TextStyle(fontSize: 12, color: AppColors.slate)),
                trailing: Radio<String>(
                  value: r['code'] as String,
                  groupValue: _selectedReport,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedReport = v);
                  },
                ),
                onTap: () => setState(() => _selectedReport = r['code'] as String),
              ),
            );
          }),
          const SizedBox(height: 24),

          // Options Card
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
                const Text('Options de Génération', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Période d\'analyse', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedPreset,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('Tout le dataset')),
                              DropdownMenuItem(value: '6m', child: Text('6 derniers mois')),
                              DropdownMenuItem(value: '30d', child: Text('30 derniers jours (Mois)')),
                              DropdownMenuItem(value: '90d', child: Text('90 derniers jours (Trimestre)')),
                              DropdownMenuItem(value: '7d', child: Text('7 derniers jours')),
                              DropdownMenuItem(value: 'ytd', child: Text('Année en cours (YTD)')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedPreset = v);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Format du livrable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedFormat,
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'pdf', child: Text('Document PDF Officiel')),
                              DropdownMenuItem(value: 'csv', child: Text('Données brutes CSV')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedFormat = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isGenerating ? null : _generateReport,
                    icon: _isGenerating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.download, size: 16),
                    label: Text(_isGenerating ? 'Génération en cours...' : 'Générer et Télécharger'),
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
