import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'models.dart';

/// Thrown for any failed Lanway API call, carrying a user-friendly message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Talks directly to a single Lanway server's REST API. There is no Lanway
/// cloud — every request goes straight to the operator's own machine.
class LanwayApiClient {
  final Dio _dio;

  /// SHA-256 (hex) of the certificate the server actually presented. After a
  /// trust-on-first-use connect, persist this on the [ServerConnection] so later
  /// connections are pinned to the same certificate.
  String? observedCertSha256;

  LanwayApiClient(ServerConnection conn)
      : _dio = Dio(BaseOptions(
          baseUrl: conn.baseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
          headers: {'Authorization': 'Bearer ${conn.apiKey}'},
          validateStatus: (s) => s != null && s < 500,
        )) {
    // The management API uses a self-signed certificate (it keeps the access key
    // off the wire). We pin it trust-on-first-use: capture the certificate's
    // fingerprint on the first connect, then on every later connect accept only
    // the exact same certificate — so a network attacker can't substitute their
    // own cert and capture the bearer key. An unpinned connection (first use /
    // upgraded from an older build) accepts the cert once to record it.
    final pinned = conn.certSha256;
    final adapter = _dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () => HttpClient()
        ..badCertificateCallback = (cert, host, port) {
          final fingerprint = sha256.convert(cert.der).toString();
          observedCertSha256 = fingerprint;
          return pinned == null || fingerprint == pinned;
        };
    }
  }

  /// Health check — does not require a valid key, used to test reachability.
  Future<ServerHealth> health() async {
    final res = await _get('/api/health');
    return ServerHealth.fromJson(res);
  }

  Future<ServerStats> stats() async {
    final res = await _get('/api/stats');
    return ServerStats.fromJson(res);
  }

  /// Forces an immediate traffic poll on the server and returns a diagnostic:
  /// how many user-stat entries Xray returned, the new total, and any error.
  Future<({int statEntries, int totalBytes, String? error})> pollUsage() async {
    final res = await _request('POST', '/api/usage/poll');
    final err = res['error'];
    return (
      statEntries: (res['stat_entries'] as num?)?.toInt() ?? 0,
      totalBytes: (res['total_bytes'] as num?)?.toInt() ?? 0,
      error: (err is String && err.isNotEmpty) ? err : null,
    );
  }

  Future<List<VpnUser>> listUsers() async {
    final res = await _get('/api/users');
    final list = (res['users'] as List?) ?? const [];
    return list.map((e) => VpnUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserWithLinks> createUser({required String name, required double dataLimitGB}) async {
    final res = await _request('POST', '/api/users', data: {
      'name': name,
      'data_limit_gb': dataLimitGB,
    });
    return UserWithLinks.fromJson(res);
  }

  Future<void> deleteUser(String id) async {
    await _request('DELETE', '/api/users/$id', expectBody: false);
  }

  Future<UserWithLinks> userKey(String id) async {
    final res = await _get('/api/users/$id/key');
    return UserWithLinks.fromJson(res);
  }

  Future<Map<String, dynamic>> _get(String path) => _request('GET', path);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Object? data,
    bool expectBody = true,
  }) async {
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: data,
        options: Options(method: method),
      );
      final code = res.statusCode ?? 0;
      if (code >= 400) {
        final body = res.data;
        final msg = body is Map && body['error'] is String
            ? body['error'] as String
            : 'Request failed ($code)';
        throw ApiException(msg, statusCode: code);
      }
      if (!expectBody) return const {};
      final body = res.data;
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        throw ApiException('Cannot reach the server. Check the address and that it is online.');
      }
      throw ApiException('Network error: ${e.message ?? e.type.name}');
    }
  }
}
