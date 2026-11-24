import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/theme/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'demo@merchantpay.dz');
  final _passwordController = TextEditingController(text: 'Demo@2026');
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = ref.read(apiClientProvider);
    try {
      final res = await client.post('/auth/login/', data: {
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
      });

      if (res.statusCode == 200) {
        final access = res.data['access'];
        final refresh = res.data['refresh'];
        final user = res.data['user'];

        await TokenStorage.saveTokens(access: access, refresh: refresh);
        await TokenStorage.saveUserJson(jsonEncode(user));

        ref.read(authStateProvider.notifier).setLoggedIn(user);

        if (mounted) {
          if (user['role'] == 'ADMIN') {
            context.go('/a/dashboard');
          } else {
            context.go('/m/dashboard');
          }
        }
      }
    } on DioException catch (e) {
      String msg = "Identifiants invalides ou compte inactif.";
      if (e.response?.data != null) {
        final d = e.response!.data;
        if (d is Map && d.containsKey('message')) {
          msg = d['message'];
        } else if (d is Map && d.containsKey('non_field_errors')) {
          msg = (d['non_field_errors'] as List).first.toString();
        }
      }
      setState(() {
        _errorMessage = msg;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Une erreur imprévue est survenue.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _fillCredentials(String email, String pass) {
    setState(() {
      _emailController.text = email;
      _passwordController.text = pass;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // SATIM Brand Logo Placeholder
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'S',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MERCHANT PAY',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const Text(
                        'FINOVIA × ENSM × SATIM Hackathon 2026',
                        style: TextStyle(fontSize: 12, color: AppColors.slate),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Text(
                        'Adresse email',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'commercant@merchantpay.dz',
                          prefixIcon: Icon(Icons.email_outlined, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Ce champ est requis';
                          if (!val.contains('@')) return 'Adresse email invalide';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Mot de passe',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.length < 8) return 'Minimum 8 caractères';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => context.go('/register'),
                        child: const Text("Créer un compte commerçant"),
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Comptes de démonstration rapide :',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.slate),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            label: const Text('Marchand Demo', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.store, size: 14),
                            onPressed: () => _fillCredentials('demo@merchantpay.dz', 'Demo@2026'),
                          ),
                          ActionChip(
                            label: const Text('Admin SATIM', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.security, size: 14),
                            onPressed: () => _fillCredentials('admin@satim.dz', 'Admin@2026'),
                          ),
                          ActionChip(
                            label: const Text('Analyste Fraude', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.analytics_outlined, size: 14),
                            onPressed: () => _fillCredentials('analyste@satim.dz', 'Admin@2026'),
                          ),
                          ActionChip(
                            label: const Text('Observateur', style: TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.visibility_outlined, size: 14),
                            onPressed: () => _fillCredentials('viewer@satim.dz', 'Admin@2026'),
                          ),
                        ],
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
