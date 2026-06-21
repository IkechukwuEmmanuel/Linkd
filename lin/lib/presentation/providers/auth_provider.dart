// Riverpod providers for authentication state management

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../core/constants/app_constants.dart';
import '../../domain/entities/entities.dart';
import '../../data/datasources/remote/linkd_api_client.dart';

// ==================== DEPENDENCIES ====================

final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized in main()');
});

final apiClientProvider = Provider<LinkdApiClient>((ref) {
  final dio = ref.watch(dioProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return LinkdApiClient(dio, prefs);
});

// ==================== AUTH STATE ====================

class AuthState {
  final User? user;
  final String? token;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  AuthState({
    this.user,
    this.token,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    User? user,
    String? token,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      user: user ?? this.user,
      token: token ?? this.token,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final LinkdApiClient apiClient;
  final SharedPreferences prefs;

  AuthNotifier(this.apiClient, this.prefs)
      : super(
          AuthState(
            isAuthenticated: prefs.getBool('is_authenticated') ?? false,
            user: _loadUserFromPrefs(prefs),
            token: prefs.getString('auth_token'),
          ),
        );

  static User? _loadUserFromPrefs(SharedPreferences prefs) {
    final userJson = prefs.getString('user_json');
    if (userJson != null) {
      try {
        return User.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Persist the resolved user so it can be restored on next app launch.
  Future<void> _persistUser(User user) async {
    await prefs.setString('user_json', jsonEncode(user.toJson()));
  }

  /// Persist a Supabase session and resolve the local user via the backend
  /// bridge (GET /auth/me with the Supabase access token).
  Future<void> _completeSupabaseSession(supa.AuthResponse res) async {
    final token = res.session?.accessToken;
    if (token == null) {
      throw Exception('Check your email to confirm your account, then sign in.');
    }
    await prefs.setString('auth_token', token);
    final user = await apiClient.getMe();
    await prefs.setBool('is_authenticated', true);
    await prefs.setInt('user_id', user.id);
    await _persistUser(user);
    state = state.copyWith(
      user: user,
      token: token,
      isLoading: false,
      isAuthenticated: true,
    );
  }

  Future<void> signup({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (AppConstants.useSupabaseAuth) {
        final res = await supa.Supabase.instance.client.auth
            .signUp(email: email, password: password);
        await _completeSupabaseSession(res);
        return;
      }
      final response = await apiClient.signup(email: email, password: password);
      await prefs.setBool('is_authenticated', true);
      await prefs.setInt('user_id', response.user.id);
      await _persistUser(response.user);
      state = state.copyWith(
        user: response.user,
        token: response.token,
        isLoading: false,
        isAuthenticated: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> signin({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      if (AppConstants.useSupabaseAuth) {
        final res = await supa.Supabase.instance.client.auth
            .signInWithPassword(email: email, password: password);
        await _completeSupabaseSession(res);
        return;
      }
      final response = await apiClient.signin(email: email, password: password);
      await prefs.setBool('is_authenticated', true);
      await prefs.setInt('user_id', response.user.id);
      await _persistUser(response.user);
      state = state.copyWith(
        user: response.user,
        token: response.token,
        isLoading: false,
        isAuthenticated: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> demoSignin() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await apiClient.demoSignin();
      await prefs.setBool('is_authenticated', true);
      await prefs.setInt('user_id', response.user.id);
      await _persistUser(response.user);
      state = state.copyWith(
        user: response.user,
        token: response.token,
        isLoading: false,
        isAuthenticated: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      if (AppConstants.useSupabaseAuth) {
        try {
          await supa.Supabase.instance.client.auth.signOut();
        } catch (_) {}
      }
      await apiClient.logout();
      await prefs.remove('is_authenticated');
      await prefs.remove('user_id');
      await prefs.remove('auth_token');
      await prefs.remove('user_json');
      state = AuthState();
    } catch (e) {
      rethrow;
    }
  }

  void checkAuthStatus() {
    final isAuth = prefs.getBool('is_authenticated') ?? false;
    state = state.copyWith(isAuthenticated: isAuth);
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthNotifier(apiClient, prefs);
});

// Get current user
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.user;
});

// Check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.isAuthenticated;
});

// Get auth token
final authTokenProvider = Provider<String?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.token;
});
