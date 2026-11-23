import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref);
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final Map<String, dynamic>? user;
  final String? errorMessage;

  AuthState({
    this.isAuthenticated = false,
    this.isLoading = true,
    this.user,
    this.errorMessage,
  });

  bool get isMerchant => user != null && user!['role'] == 'MERCHANT';
  bool get isAdmin => user != null && user!['role'] == 'ADMIN';
  String get adminLevel => user?['admin_level'] ?? 'VIEWER';
  bool get canWrite => !isAdmin || adminLevel != 'VIEWER';
  bool get isSuperAdmin => isAdmin && adminLevel == 'SUPER_ADMIN';

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    Map<String, dynamic>? user,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState(isLoading: true)) {
    checkAuth();
  }

  Future<void> checkAuth() async {
    final token = await TokenStorage.getAccessToken();
    final userJson = await TokenStorage.getUserJson();
    if (token != null && userJson != null) {
      try {
        final userData = jsonDecode(userJson);
        state = AuthState(isAuthenticated: true, isLoading: false, user: userData);
        return;
      } catch (_) {}
    }
    state = AuthState(isAuthenticated: false, isLoading: false);
  }

  void setLoggedIn(Map<String, dynamic> user) {
    state = AuthState(isAuthenticated: true, isLoading: false, user: user);
  }

  Future<void> logout() async {
    await TokenStorage.clear();
    state = AuthState(isAuthenticated: false, isLoading: false);
  }
}

class ApiClient {
  final Ref ref;
  late final Dio dio;

  // Points to Django backend (supports local dev on web/mobile)
  static const String baseUrl = 'http://localhost:8000/api/v1';

  ApiClient(this.ref) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401 && !error.requestOptions.path.contains('/auth/login')) {
            // Attempt token refresh
            final refreshToken = await TokenStorage.getRefreshToken();
            if (refreshToken != null) {
              try {
                final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
                final res = await refreshDio.post('/auth/refresh/', data: {'refresh': refreshToken});
                if (res.statusCode == 200) {
                  final newAccess = res.data['access'];
                  final newRefresh = res.data['refresh'] ?? refreshToken;
                  await TokenStorage.saveTokens(access: newAccess, refresh: newRefresh);

                  // Retry the original request
                  error.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
                  final cloneReq = await dio.request(
                    error.requestOptions.path,
                    options: Options(
                      method: error.requestOptions.method,
                      headers: error.requestOptions.headers,
                    ),
                    data: error.requestOptions.data,
                    queryParameters: error.requestOptions.queryParameters,
                  );
                  return handler.resolve(cloneReq);
                }
              } catch (_) {
                // Refresh failed: forced logout
                await ref.read(authStateProvider.notifier).logout();
              }
            } else {
              await ref.read(authStateProvider.notifier).logout();
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data}) {
    return dio.post(path, data: data);
  }

  Future<Response> patch(String path, {dynamic data}) {
    return dio.patch(path, data: data);
  }

  Future<Response> delete(String path) {
    return dio.delete(path);
  }
}
