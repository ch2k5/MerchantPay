from django.urls import path

from apps.merchants.admin_views import (
    AdminAnalyticsExportView,
    AdminAnalyticsView,
    AdminAuditLogListView,
    AdminDashboardView,
    AdminMerchantActivationView,
    AdminMerchantDetailView,
    AdminMerchantListView,
    AdminMerchantStatsView,
    AdminMerchantTransactionsView,
    AdminReportGenerateView,
    AdminReportMerchantsView,
    AdminReportPlatformView,
    AdminReportRiskView,
    AdminRiskFlagDetailView,
    AdminRiskFlagListView,
    AdminRiskFlagNoteCreateView,
    AdminRiskFlagStatusView,
    AdminRiskScanView,
    AdminRiskSummaryView,
    AdminTransactionDetailView,
    AdminTransactionExportView,
    AdminTransactionListView,
    AdminUserDetailView,
    AdminUserListCreateView,
)

urlpatterns = [
    # Global Supervision
    path("dashboard/", AdminDashboardView.as_view(), name="admin-dashboard"),
    path("analytics/", AdminAnalyticsView.as_view(), name="admin-analytics"),
    path("analytics/export/", AdminAnalyticsExportView.as_view(), name="admin-analytics-export"),
    # Merchants Management
    path("merchants/", AdminMerchantListView.as_view(), name="admin-merchants-list"),
    path("merchants/<uuid:pk>/", AdminMerchantDetailView.as_view(), name="admin-merchants-detail"),
    path(
        "merchants/<uuid:pk>/<str:action_type>/",
        AdminMerchantActivationView.as_view(),
        name="admin-merchants-activation",
    ),
    path("merchants/<uuid:pk>/stats/", AdminMerchantStatsView.as_view(), name="admin-merchants-stats"),
    path(
        "merchants/<uuid:pk>/transactions/",
        AdminMerchantTransactionsView.as_view(),
        name="admin-merchants-transactions",
    ),
    # Transactions Explorer
    path("transactions/", AdminTransactionListView.as_view(), name="admin-transactions-list"),
    path("transactions/export/", AdminTransactionExportView.as_view(), name="admin-transactions-export"),
    path("transactions/<uuid:pk>/", AdminTransactionDetailView.as_view(), name="admin-transactions-detail"),
    # Risk & Fraud Engine
    path("risk/", AdminRiskFlagListView.as_view(), name="admin-risk-alias"),
    path("risk/<uuid:pk>/", AdminRiskFlagDetailView.as_view(), name="admin-risk-detail-alias"),
    path("risk/<uuid:pk>/status/", AdminRiskFlagStatusView.as_view(), name="admin-risk-status-alias"),
    path("risk/<uuid:pk>/notes/", AdminRiskFlagNoteCreateView.as_view(), name="admin-risk-notes-alias"),
    path("risk/flags/", AdminRiskFlagListView.as_view(), name="admin-risk-flags-list"),
    path("risk/flags/<uuid:pk>/", AdminRiskFlagDetailView.as_view(), name="admin-risk-flags-detail"),
    path("risk/flags/<uuid:pk>/status/", AdminRiskFlagStatusView.as_view(), name="admin-risk-flags-status"),
    path("risk/flags/<uuid:pk>/notes/", AdminRiskFlagNoteCreateView.as_view(), name="admin-risk-flags-notes"),
    path("risk/scan/", AdminRiskScanView.as_view(), name="admin-risk-scan"),
    path("risk/summary/", AdminRiskSummaryView.as_view(), name="admin-risk-summary"),
    # Reports
    path("reports/generate/", AdminReportGenerateView.as_view(), name="admin-reports-generate"),
    path("reports/platform/", AdminReportPlatformView.as_view(), name="admin-reports-platform"),
    path("reports/merchants/", AdminReportMerchantsView.as_view(), name="admin-reports-merchants"),
    path("reports/risk/", AdminReportRiskView.as_view(), name="admin-reports-risk"),
    # Audit Logs (SUPER_ADMIN only)
    path("audit/", AdminAuditLogListView.as_view(), name="admin-audit-alias"),
    path("audit-logs/", AdminAuditLogListView.as_view(), name="admin-audit-logs"),
    # Admin Users & Roles (SUPER_ADMIN only)
    path("users/", AdminUserListCreateView.as_view(), name="admin-users-list"),
    path("users/<uuid:pk>/", AdminUserDetailView.as_view(), name="admin-users-detail"),
]
