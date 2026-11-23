import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/responsive_shell.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/merchant_dashboard/presentation/merchant_dashboard_screen.dart';
import '../../features/transactions/presentation/merchant_transactions_screen.dart';
import '../../features/analytics/presentation/merchant_collections_screen.dart';
import '../../features/analytics/presentation/merchant_analytics_screen.dart';
import '../../features/alerts/presentation/merchant_alerts_screen.dart';
import '../../features/simulator/presentation/merchant_simulator_screen.dart';
import '../../features/profile/presentation/merchant_profile_screen.dart';
import '../../features/admin/dashboard/presentation/admin_dashboard_screen.dart';
import '../../features/admin/merchants/presentation/admin_merchants_screen.dart';
import '../../features/admin/transactions/presentation/admin_transactions_screen.dart';
import '../../features/admin/risk/presentation/admin_risk_screen.dart';
import '../../features/admin/reports/presentation/admin_reports_screen.dart';
import '../../features/admin/audit/presentation/admin_audit_screen.dart';
import '../../features/admin/users/presentation/admin_users_screen.dart';

final routerRefreshProvider = Provider<Listenable>((ref) {
  final notifier = ValueNotifier<AuthState>(ref.watch(authStateProvider));
  ref.listen<AuthState>(authStateProvider, (_, next) {
    notifier.value = next;
  });
  return notifier;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(routerRefreshProvider);
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';

      if (!authState.isAuthenticated) {
        return isAuthRoute ? null : '/login';
      }

      // If authenticated and on auth page, redirect to home based on role
      if (isAuthRoute) {
        return authState.isMerchant ? '/m/dashboard' : '/a/dashboard';
      }

      // Role isolation: prevent merchant from accessing admin routes
      if (authState.isMerchant && loc.startsWith('/a/')) {
        return '/m/dashboard';
      }

      // Prevent admin from accessing merchant routes
      if (authState.isAdmin && loc.startsWith('/m/')) {
        return '/a/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ResponsiveShell(
            currentPath: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          // Merchant Routes
          GoRoute(
            path: '/m/dashboard',
            builder: (context, state) => const MerchantDashboardScreen(),
          ),
          GoRoute(
            path: '/m/transactions',
            builder: (context, state) => const MerchantTransactionsScreen(),
          ),
          GoRoute(
            path: '/m/collections',
            builder: (context, state) => const MerchantCollectionsScreen(),
          ),
          GoRoute(
            path: '/m/analytics',
            builder: (context, state) => const MerchantAnalyticsScreen(),
          ),
          GoRoute(
            path: '/m/alerts',
            builder: (context, state) => const MerchantAlertsScreen(),
          ),
          GoRoute(
            path: '/m/simulator',
            builder: (context, state) => const MerchantSimulatorScreen(),
          ),
          GoRoute(
            path: '/m/profile',
            builder: (context, state) => const MerchantProfileScreen(),
          ),

          // SATIM Admin Routes
          GoRoute(
            path: '/a/dashboard',
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/a/merchants',
            builder: (context, state) => const AdminMerchantsScreen(),
          ),
          GoRoute(
            path: '/a/transactions',
            builder: (context, state) => const AdminTransactionsScreen(),
          ),
          GoRoute(
            path: '/a/risk',
            builder: (context, state) => const AdminRiskScreen(),
          ),
          GoRoute(
            path: '/a/reports',
            builder: (context, state) => const AdminReportsScreen(),
          ),
          GoRoute(
            path: '/a/audit',
            builder: (context, state) => const AdminAuditScreen(),
          ),
          GoRoute(
            path: '/a/users',
            builder: (context, state) => const AdminUsersScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text(
              'Page introuvable (404)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              'L\'adresse « ${state.matchedLocation} » n\'existe pas.',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Retour à l\'accueil'),
            ),
          ],
        ),
      ),
    ),
  );
});
