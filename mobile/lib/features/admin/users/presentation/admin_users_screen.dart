import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common_widgets.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.get('/admin/users/');
      if (res.statusCode == 200) {
        setState(() {
          _users = res.data is List ? res.data : (res.data['results'] ?? []);
        });
      }
    } catch (e) {
      setState(() {
        _error = "Impossible de récupérer les utilisateurs administrateurs.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showCreateUserDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    String selectedRole = 'ANALYST';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Créer un Nouvel Administrateur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email institutionnel (@satim.dz)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe initial (8+ car.)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: firstNameController,
                        decoration: const InputDecoration(labelText: 'Prénom'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lastNameController,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rôle SATIM'),
                  items: const [
                    DropdownMenuItem(value: 'SUPER_ADMIN', child: Text('Administrateur Principal (SUPER_ADMIN)')),
                    DropdownMenuItem(value: 'ANALYST', child: Text('Analyste Risque & Fraude (ANALYST)')),
                    DropdownMenuItem(value: 'VIEWER', child: Text('Observateur / Auditeur (VIEWER)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedRole = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (emailController.text.trim().isEmpty || passwordController.text.length < 8) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Veuillez remplir correctement les champs.")));
                  return;
                }
                try {
                  final client = ref.read(apiClientProvider);
                  final res = await client.post(
                    '/admin/users/',
                    data: {
                      'email': emailController.text.trim(),
                      'password': passwordController.text,
                      'first_name': firstNameController.text.trim(),
                      'last_name': lastNameController.text.trim(),
                      'role': selectedRole,
                    },
                  );
                  if (res.statusCode == 201 && ctx.mounted) {
                    Navigator.pop(ctx);
                    _fetchUsers();
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Échec de la création du compte.")));
                  }
                }
              },
              child: const Text('Créer le compte'),
            ),
          ],
        ),
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
                  Text('Équipe & Rôles Administrateurs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.ink)),
                  Text('Gestion des accès des analystes, auditeurs et superviseurs SATIM', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
              FilledButton.icon(
                onPressed: _showCreateUserDialog,
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Nouvel Administrateur'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Users Table Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: _isLoading
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _fetchUsers)
                    : _users.isEmpty
                        ? const AppEmptyState(title: "Aucun utilisateur trouvé", message: "Aucun compte administrateur enregistré.")
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Utilisateur')),
                                DataColumn(label: Text('Rôle')),
                                DataColumn(label: Text('Statut')),
                                DataColumn(label: Text('Date de création')),
                              ],
                              rows: _users.map((u) {
                                final role = u['role'] ?? 'ANALYST';
                                Color roleColor = role == 'SUPER_ADMIN' ? AppColors.primary : (role == 'ANALYST' ? AppColors.cibBlue : AppColors.muted);
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim().isEmpty ? u['email'] : '${u['first_name']} ${u['last_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          Text(u['email'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: roleColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          u['role_display'] ?? role,
                                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        u['is_active'] == true ? 'Actif' : 'Inactif',
                                        style: TextStyle(
                                          color: u['is_active'] == true ? AppColors.success : AppColors.danger,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(formatDate(u['created_at']), style: const TextStyle(fontSize: 12))),
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
