import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../network/api_client.dart';
import '../theme/app_colors.dart';

class NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;

  const NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
  });
}

class ResponsiveShell extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const ResponsiveShell({
    super.key,
    required this.child,
    required this.currentPath,
  });

  static const merchantItems = [
    NavItem(
      label: 'Tableau de bord',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      path: '/m/dashboard',
    ),
    NavItem(
      label: 'Transactions',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      path: '/m/transactions',
    ),
    NavItem(
      label: 'Encaissements',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      path: '/m/collections',
    ),
    NavItem(
      label: 'Analyses',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
      path: '/m/analytics',
    ),
    NavItem(
      label: 'Alertes',
      icon: Icons.notifications_none_outlined,
      selectedIcon: Icons.notifications,
      path: '/m/alerts',
    ),
    NavItem(
      label: 'Simulateur',
      icon: Icons.auto_graph_outlined,
      selectedIcon: Icons.auto_graph,
      path: '/m/simulator',
    ),
    NavItem(
      label: 'Profil',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      path: '/m/profile',
    ),
  ];

  static const adminItems = [
    NavItem(
      label: 'Supervision',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
      path: '/a/dashboard',
    ),
    NavItem(
      label: 'Commerçants',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront,
      path: '/a/merchants',
    ),
    NavItem(
      label: 'Transactions',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      path: '/a/transactions',
    ),
    NavItem(
      label: 'Risque & Fraude',
      icon: Icons.security_outlined,
      selectedIcon: Icons.security,
      path: '/a/risk',
    ),
    NavItem(
      label: 'Rapports',
      icon: Icons.summarize_outlined,
      selectedIcon: Icons.summarize,
      path: '/a/reports',
    ),
    NavItem(
      label: "Journal d'audit",
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      path: '/a/audit',
    ),
    NavItem(
      label: 'Administrateurs',
      icon: Icons.admin_panel_settings_outlined,
      selectedIcon: Icons.admin_panel_settings,
      path: '/a/users',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final isMerchant = authState.isMerchant;
    final items = isMerchant ? merchantItems : adminItems;

    int currentIndex = items.indexWhere((it) => currentPath.startsWith(it.path));
    if (currentIndex == -1) currentIndex = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 1024) {
          // Desktop / Web: Permanent Left Sidebar + Top Bar
          return Scaffold(
            body: Row(
              children: [
                _buildDesktopSidebar(context, ref, authState, items, currentIndex),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopHeader(context, ref, authState),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else if (constraints.maxWidth >= 600) {
          // Tablet: NavigationRail
          return Scaffold(
            appBar: AppBar(
              title: Text(_portalTitle(authState)),
              actions: [_buildUserMenu(context, ref, authState)],
            ),
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (idx) => context.go(items[idx].path),
                  labelType: NavigationRailLabelType.selected,
                  destinations: items
                      .map((it) => NavigationRailDestination(
                            icon: Icon(it.icon),
                            selectedIcon: Icon(it.selectedIcon, color: AppColors.primary),
                            label: Text(it.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        } else {
          // Mobile: Bottom Navigation (up to 5 items)
          final mobileItems = items.take(5).toList();
          return Scaffold(
            appBar: AppBar(
              title: Text(_portalTitle(authState)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () {
                    if (isMerchant) context.go('/m/alerts');
                  },
                ),
                _buildUserMenu(context, ref, authState),
              ],
            ),
            drawer: items.length > 5 ? _buildMobileDrawer(context, ref, authState, items) : null,
            body: child,
            bottomNavigationBar: NavigationBar(
              selectedIndex: currentIndex < 5 ? currentIndex : 0,
              onDestinationSelected: (idx) => context.go(mobileItems[idx].path),
              destinations: mobileItems
                  .map((it) => NavigationDestination(
                        icon: Icon(it.icon),
                        selectedIcon: Icon(it.selectedIcon, color: AppColors.primary),
                        label: it.label,
                      ))
                  .toList(),
            ),
          );
        }
      },
    );
  }

  String _portalTitle(AuthState authState) {
    if (authState.isMerchant) {
      final name = authState.user?['merchant']?['business_name'] ?? 'Commerçant';
      return 'MERCHANT PAY — $name';
    }
    return 'SATIM — Administration & Surveillance';
  }

  Widget _buildDesktopSidebar(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
    List<NavItem> items,
    int currentIndex,
  ) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        children: [
          // Brand Header with SATIM logo placeholder
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
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
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MERCHANT PAY',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.ink,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      'FINOVIA × SATIM',
                      style: TextStyle(fontSize: 10, color: AppColors.slate),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Nav items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final it = items[idx];
                final isSelected = idx == currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    leading: Icon(
                      isSelected ? it.selectedIcon : it.icon,
                      color: isSelected ? AppColors.primary : AppColors.slate,
                      size: 20,
                    ),
                    title: Text(
                      it.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? AppColors.primary : AppColors.ink,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: AppColors.primaryTint,
                    onTap: () => context.go(it.path),
                  ),
                );
              },
            ),
          ),
          // Version info
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            child: const Text(
              'v1.0.0-hackathon',
              style: TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, WidgetRef ref, AuthState authState) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: authState.isMerchant ? const Color(0xFFE8F5E9) : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  authState.isMerchant ? "ESPACE COMMERÇANT" : "ADMINISTRATION SATIM",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: authState.isMerchant ? AppColors.success : AppColors.info,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                authState.isMerchant
                    ? (authState.user?['merchant']?['business_name'] ?? '')
                    : 'Surveillance et Gestion Interbancaire',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          Row(
            children: [
              if (authState.isMerchant) ...[
                IconButton(
                  icon: const Icon(Icons.notifications_none, color: AppColors.slate),
                  tooltip: 'Alertes',
                  onPressed: () => context.go('/m/alerts'),
                ),
                const SizedBox(width: 8),
              ],
              _buildUserMenu(context, ref, authState),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenu(BuildContext context, WidgetRef ref, AuthState authState) {
    final email = authState.user?['email'] ?? '';
    final name = authState.user?['full_name'] ?? email;

    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'logout') {
          ref.read(authStateProvider.notifier).logout();
          context.go('/login');
        } else if (val == 'profile') {
          context.go('/m/profile');
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink)),
              Text(email, style: const TextStyle(fontSize: 11, color: AppColors.slate)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (authState.isMerchant)
          const PopupMenuItem(value: 'profile', child: Text('Profil & Paramètres')),
        const PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 16, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Déconnexion', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primaryTint,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(
    BuildContext context,
    WidgetRef ref,
    AuthState authState,
    List<NavItem> items,
  ) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primary),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                _portalTitle(authState),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: items.map((it) {
                return ListTile(
                  leading: Icon(it.icon),
                  title: Text(it.label),
                  onTap: () {
                    Navigator.pop(context);
                    context.go(it.path);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
