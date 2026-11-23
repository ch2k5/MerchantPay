import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/theme/app_colors.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _rcCtrl = TextEditingController();
  final _wilayaCtrl = TextEditingController(text: 'Alger');
  final _phoneCtrl = TextEditingController();
  final _goalCtrl = TextEditingController(text: '1500000');
  String _category = 'Restauration';
  bool _isLoading = false;
  String? _error;

  final categories = [
    'Restauration',
    'Commerce de détail',
    'Pharmacie',
    'Alimentation',
    'Électronique',
    'Habillement',
    'Services',
    'Carburant',
    'Hôtellerie',
    'Autre',
  ];

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final client = ref.read(apiClientProvider);
    try {
      final res = await client.post('/auth/register/', data: {
        'email': _emailCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'full_name': _nameCtrl.text.trim(),
        'business_name': _businessNameCtrl.text.trim(),
        'merchant_category': _category,
        'registration_number': _rcCtrl.text.trim(),
        'wilaya': _wilayaCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'monthly_goal': _goalCtrl.text.trim(),
      });

      if (res.statusCode == 201) {
        final access = res.data['access'];
        final refresh = res.data['refresh'];
        final user = res.data['user'];

        await TokenStorage.saveTokens(access: access, refresh: refresh);
        await TokenStorage.saveUserJson(jsonEncode(user));
        ref.read(authStateProvider.notifier).setLoggedIn(user);

        context.go('/m/dashboard');
      }
    } catch (e) {
      setState(() {
        _error = "Erreur lors de l'inscription. Vérifiez que l'email est unique et le mot de passe >= 8 caractères.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Inscription Commerçant"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "Créer votre Espace Commerçant",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Connectez vos terminaux CIB & EDAHABIA à l'intelligence financière.",
                        style: TextStyle(fontSize: 13, color: AppColors.slate),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom et Prénom du gérant *'),
                        validator: (v) => v!.isEmpty ? 'Requis' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email de connexion *'),
                        validator: (v) => v!.contains('@') ? null : 'Email valide requis',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Mot de passe (8 caractères min) *'),
                        validator: (v) => v!.length >= 8 ? null : 'Minimum 8 caractères',
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _businessNameCtrl,
                        decoration: const InputDecoration(labelText: 'Raison sociale / Enseigne commerciale *'),
                        validator: (v) => v!.isEmpty ? 'Requis' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _category,
                        decoration: const InputDecoration(labelText: "Catégorie d'activité *"),
                        items: categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() => _category = v!),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _rcCtrl,
                              decoration: const InputDecoration(labelText: 'Registre de Commerce (RC) *'),
                              validator: (v) => v!.isEmpty ? 'Requis' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _wilayaCtrl,
                              decoration: const InputDecoration(labelText: 'Wilaya *'),
                              validator: (v) => v!.isEmpty ? 'Requis' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(labelText: 'Numéro de téléphone'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _goalCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Objectif mensuel (DZD)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("Finaliser l'inscription"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
