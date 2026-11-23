import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common_widgets.dart';

class MerchantProfileScreen extends ConsumerStatefulWidget {
  const MerchantProfileScreen({super.key});

  @override
  ConsumerState<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends ConsumerState<MerchantProfileScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  Map<String, dynamic>? _profile;

  final _businessNameController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _wilayaController = TextEditingController();
  final _communeController = TextEditingController();
  final _goalController = TextEditingController();

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _contactNameController.dispose();
    _phoneController.dispose();
    _wilayaController.dispose();
    _communeController.dispose();
    _goalController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/merchant/profile/');
      if (res.statusCode == 200) {
        final d = res.data;
        setState(() {
          _profile = d;
          _businessNameController.text = d['business_name'] ?? '';
          _contactNameController.text = d['contact_name'] ?? '';
          _phoneController.text = d['phone'] ?? '';
          _wilayaController.text = d['wilaya'] ?? '';
          _communeController.text = d['commune'] ?? '';
          _goalController.text = d['monthly_goal'] != null ? d['monthly_goal'].toString() : '';
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de charger les données du profil.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final client = ref.read(apiClientProvider);
      final goalVal = double.tryParse(_goalController.text);
      final payload = <String, dynamic>{
        'business_name': _businessNameController.text.trim(),
        'contact_name': _contactNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'wilaya': _wilayaController.text.trim(),
        'commune': _communeController.text.trim(),
      };
      if (goalVal != null) {
        payload['monthly_goal'] = goalVal;
      }

      final res = await client.patch('/merchant/profile/', data: payload);
      if (res.statusCode == 200) {
        setState(() {
          _profile = res.data;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profil mis à jour avec succès.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de la sauvegarde du profil.")),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le mot de passe doit contenir au moins 8 caractères.")),
      );
      return;
    }
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post(
        '/auth/password/change/',
        data: {
          'old_password': _oldPasswordController.text,
          'new_password': _newPasswordController.text,
        },
      );
      if (res.statusCode == 200) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Mot de passe modifié avec succès.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec du changement de mot de passe.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _fetchProfile);
    }

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
                    'Profil Commerçant',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink),
                  ),
                  Text(
                    'Informations légales, coordonnées et objectifs mensuels',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(authStateProvider.notifier).logout();
                  context.go('/login');
                },
                icon: const Icon(Icons.logout, size: 16, color: AppColors.danger),
                label: const Text('Déconnexion', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Informational Cards Row
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
                const Text('Informations Générales & Statut', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 32,
                  runSpacing: 16,
                  children: [
                    _buildMetaItem('Identifiant Unique', _profile?['id']?.toString() ?? '-'),
                    _buildMetaItem('Numéro d\'Enregistrement (RC/NIF)', _profile?['legal_id'] ?? '-'),
                    _buildMetaItem('Secteur MCC', _profile?['mcc_display'] ?? _profile?['mcc'] ?? '-'),
                    _buildMetaItem('Date d\'Adhésion', formatDate(_profile?['created_at'])),
                    _buildMetaItem('Statut', _profile?['status'] == 'ACTIVE' ? 'Actif' : 'Inactif'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Edit Form
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
                const Text('Modifier les Coordonnées', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _businessNameController,
                  decoration: const InputDecoration(labelText: 'Raison Sociale / Enseigne'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _contactNameController,
                        decoration: const InputDecoration(labelText: 'Nom du Contact'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(labelText: 'Téléphone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _wilayaController,
                        decoration: const InputDecoration(labelText: 'Wilaya'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _communeController,
                        decoration: const InputDecoration(labelText: 'Commune'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _goalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Objectif de chiffre d\'affaires mensuel (DZD)',
                    helperText: 'Cet objectif pilote l\'indicateur d\'avancement de votre tableau de bord.',
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save, size: 16),
                    label: const Text('Enregistrer les modifications'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Change Password Card
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
                const Text('Sécurité du Compte (Mot de passe)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.ink)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _oldPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Mot de passe actuel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _newPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Nouveau mot de passe'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _changePassword,
                    child: const Text('Mettre à jour le mot de passe'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ],
    );
  }
}
