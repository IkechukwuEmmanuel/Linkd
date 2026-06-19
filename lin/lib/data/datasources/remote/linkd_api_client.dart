// Linkd API Client - handles all HTTP requests to backend

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/entities.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';

class LinkdApiClient {
  final Dio _dio;
  final SharedPreferences _prefs;

  LinkdApiClient(this._dio, this._prefs) {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Add auth token
          final token = _prefs.getString('auth_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['Content-Type'] = 'application/json';
          AppLogger.debug('API Request: ${options.method} ${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.debug('API Response: ${response.statusCode} ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (error, handler) {
          AppLogger.error('API Error: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  // ==================== AUTH ENDPOINTS ====================

  Future<AuthResponse> signup({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/auth/signup',
        data: {
          'email': email,
          'password': password,
        },
      );
      final authResponse = AuthResponse.fromJson(response.data);
      await _prefs.setString('auth_token', authResponse.token);
      return authResponse;
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResponse> signin({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/auth/signin',
        data: {
          'email': email,
          'password': password,
        },
      );
      final authResponse = AuthResponse.fromJson(response.data);
      await _prefs.setString('auth_token', authResponse.token);
      return authResponse;
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthResponse> demoSignin() async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/auth/demo-signin',
      );
      final authResponse = AuthResponse.fromJson(response.data);
      await _prefs.setString('auth_token', authResponse.token);
      return authResponse;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _prefs.remove('auth_token');
      await _prefs.remove('user_id');
    } catch (e) {
      rethrow;
    }
  }

  /// Export all of the current user's data (GDPR/CCPA portability).
  Future<Map<String, dynamic>> exportMyData() async {
    final response =
        await _dio.get('${AppConstants.apiBaseUrl}/auth/me/export');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Permanently delete the current user's account and all associated data.
  Future<void> deleteMyAccount() async {
    await _dio.delete('${AppConstants.apiBaseUrl}/auth/me');
  }

  // ==================== ONBOARDING ENDPOINTS ====================

  Future<Map<String, dynamic>> uploadVoicePitch({
    required int userId,
    required String filePath,
  }) async {
    try {
      FormData formData = FormData.fromMap({
        'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/onboarding/voice-pitch',
        data: formData,
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadLinkedInProfile({
    required int userId,
    required String profileUrl,
  }) async {
    try {
      FormData formData = FormData.fromMap({
        'user_id': userId,
        'profile_url': profileUrl,
      });

      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/onboarding/linkedin-profile',
        data: formData,
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== PERSONAS ENDPOINTS ====================

  Future<List<Persona>> getPersonas(int userId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/onboarding/persona',
        queryParameters: {'user_id': userId},
      );
      final personas = (response.data as List)
          .map((p) => Persona.fromJson(p))
          .toList();
      return personas;
    } catch (e) {
      rethrow;
    }
  }

  Future<Persona> getPersona(int userId, int personaId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/onboarding/persona/$personaId',
        queryParameters: {'user_id': userId},
      );
      return Persona.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Persona> updatePersona({
    required int userId,
    required int personaId,
    String? label,
    int? weight,
  }) async {
    try {
      final response = await _dio.patch(
        '${AppConstants.apiBaseUrl}/onboarding/persona/$personaId',
        queryParameters: {'user_id': userId},
        data: {
          if (label != null) 'label': label,
          if (weight != null) 'weight': weight,
        },
      );
      return Persona.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deletePersona(int userId, int personaId) async {
    try {
      await _dio.delete(
        '${AppConstants.apiBaseUrl}/onboarding/persona/$personaId',
        queryParameters: {'user_id': userId},
      );
    } catch (e) {
      rethrow;
    }
  }

  // ==================== INTERACTION ENDPOINTS ====================

  Future<Map<String, dynamic>> processInteractionAudio({
    required int userId,
    required String filePath,
    required String mode, // "live" or "recap"
  }) async {
    try {
      FormData formData = FormData.fromMap({
        'user_id': userId,
        'file': await MultipartFile.fromFile(filePath),
        'mode': mode,
      });

      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/interactions/process-audio',
        data: formData,
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== INGEST ENDPOINTS (async pipeline) ====================

  /// Upload a recorded audio file to the async ingest pipeline.
  ///
  /// Returns the `job_id` to poll via [pollIngestStatus]. The pipeline
  /// transcribes the audio and creates a Contact, surfacing `contact_id` on the
  /// status endpoint when done.
  Future<String?> ingestAudio({
    required String filePath,
    required String mode, // "live" or "recap"
    required int durationSeconds,
    String? eventName,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType('audio', 'mp4'),
      ),
      'mode': mode,
      'duration_seconds': durationSeconds,
      if (eventName != null && eventName.isNotEmpty) 'event_name': eventName,
    });

    final response = await _dio.post(
      '${AppConstants.apiBaseUrl}/ingest/audio',
      data: formData,
    );
    return response.data['job_id'] as String?;
  }

  /// Poll a single ingest job. Returns `{ job_id, status, contact_id }`.
  Future<Map<String, dynamic>> pollIngestStatus(String jobId) async {
    final response = await _dio.get(
      '${AppConstants.apiBaseUrl}/ingest/status/$jobId',
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  // ==================== FEEDBACK ENDPOINTS ====================

  Future<Map<String, dynamic>> submitPersonaFeedback({
    required int userId,
    required int personaId,
    required String feedbackType, // "approved", "rejected", "rated"
    int? rating,
    String? notes,
  }) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/feedback/persona/$personaId',
        queryParameters: {'user_id': userId},
        data: {
          'feedback_type': feedbackType,
          if (rating != null) 'rating': rating,
          if (notes != null) 'notes': notes,
        },
      );
      return response.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<Metrics> getMetrics(int userId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/feedback/metrics',
        queryParameters: {'user_id': userId},
      );
      return Metrics.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // ==================== JOB STATUS ENDPOINTS ====================

  Future<Job> getJobStatus(int userId, String jobId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/jobs/status/$jobId',
        queryParameters: {'user_id': userId},
      );
      return Job.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Job>> getJobsList(
    int userId, {
    String? status,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/jobs/list',
        queryParameters: {
          'user_id': userId,
          if (status != null) 'status': status,
          'limit': limit,
        },
      );
      final jobs = (response.data['jobs'] as List)
          .map((j) => Job.fromJson(j))
          .toList();
      return jobs;
    } catch (e) {
      rethrow;
    }
  }

  // ==================== CONTACTS ENDPOINTS ====================

  Future<List<Contact>> getContacts({
    String? event,
    bool? starred,
    String? tag,
    String sort = 'recent',
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/contacts/',
        queryParameters: {
          if (event != null) 'event': event,
          if (starred != null) 'starred': starred,
          if (tag != null) 'tag': tag,
          'sort': sort,
          'page': page,
          'limit': limit,
        },
      );
      final data = response.data['data'] as List;
      return data.map((c) => Contact.fromJson(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact> getContact(int contactId) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/contacts/$contactId',
      );
      return Contact.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact> createContact(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/contacts/',
        data: data,
      );
      return Contact.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact> updateContact(int contactId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch(
        '${AppConstants.apiBaseUrl}/contacts/$contactId',
        data: data,
      );
      return Contact.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteContact(int contactId) async {
    try {
      await _dio.delete('${AppConstants.apiBaseUrl}/contacts/$contactId');
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact> toggleStar(int contactId) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/contacts/$contactId/star',
      );
      return Contact.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<Contact> markFollowUpComplete(int contactId) async {
    try {
      final response = await _dio.post(
        '${AppConstants.apiBaseUrl}/contacts/$contactId/follow-up-complete',
      );
      return Contact.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  /// Fast text-based capture. The backend extracts/enriches asynchronously.
  Future<void> quickCapture({
    required String name,
    required String note,
    String? eventName,
  }) async {
    await _dio.post(
      '${AppConstants.apiBaseUrl}/contacts/quick-capture',
      data: {
        'name': name,
        'note': note,
        if (eventName != null && eventName.isNotEmpty) 'event_name': eventName,
      },
    );
  }

  Future<List<Contact>> searchContacts(String query) async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/contacts/search',
        queryParameters: {'q': query},
      );
      final data = response.data['data'] as List;
      return data.map((c) => Contact.fromJson(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Contact>> getUpcomingFollowUps() async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/contacts/upcoming-follow-ups',
      );
      final data = response.data['data'] as List;
      return data.map((c) => Contact.fromJson(c)).toList();
    } catch (e) {
      rethrow;
    }
  }

  // ==================== NOTIFICATIONS ENDPOINTS ====================

  /// Returns `{ unread_count, data: [...] }`.
  Future<Map<String, dynamic>> getNotifications({bool unreadOnly = false}) async {
    final response = await _dio.get(
      '${AppConstants.apiBaseUrl}/notifications/',
      queryParameters: {if (unreadOnly) 'unread_only': true},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> markNotificationRead(int id) async {
    await _dio.post('${AppConstants.apiBaseUrl}/notifications/$id/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _dio.post('${AppConstants.apiBaseUrl}/notifications/read-all');
  }

  // ==================== INSIGHTS ENDPOINTS ====================

  Future<InsightsSummary> getInsightsSummary() async {
    try {
      final response = await _dio.get(
        '${AppConstants.apiBaseUrl}/insights/summary',
      );
      return InsightsSummary.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }
}
