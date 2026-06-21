import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'api_client.dart';

/// A DigitalOcean region option offered during one-click provisioning.
class DoRegion {
  final String slug;
  final String name;
  const DoRegion(this.slug, this.name);
}

/// Display metadata (city, country, ISO-3166 alpha-2 [code]) for a region,
/// keyed by slug prefix. [code] selects the flag PNG in assets/flags/.
class RegionMeta {
  final String city;
  final String country;
  final String code; // '' = no flag (show a globe)
  const RegionMeta(this.city, this.country, {this.code = ''});
}

RegionMeta regionMeta(String slug) {
  final p = slug.length >= 3 ? slug.substring(0, 3) : slug;
  switch (p) {
    case 'nyc':
      return const RegionMeta('New York', 'United States', code: 'us');
    case 'sfo':
      return const RegionMeta('San Francisco', 'United States', code: 'us');
    case 'tor':
      return const RegionMeta('Toronto', 'Canada', code: 'ca');
    case 'lon':
      return const RegionMeta('London', 'United Kingdom', code: 'gb');
    case 'fra':
      return const RegionMeta('Frankfurt', 'Germany', code: 'de');
    case 'ams':
      return const RegionMeta('Amsterdam', 'Netherlands', code: 'nl');
    case 'sgp':
      return const RegionMeta('Singapore', 'Singapore', code: 'sg');
    case 'blr':
      return const RegionMeta('Bangalore', 'India', code: 'in');
    case 'syd':
      return const RegionMeta('Sydney', 'Australia', code: 'au');
    default:
      return RegionMeta(slug.toUpperCase(), 'DigitalOcean');
  }
}

/// Minimal DigitalOcean API client used to provision a Lanway droplet in one
/// click. The user supplies a Personal Access Token; the token stays on this
/// device and is sent only to api.digitalocean.com.
class DigitalOceanClient {
  final Dio _dio;

  DigitalOceanClient(String token)
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.digitalocean.com/v2',
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (s) => s != null && s < 500,
        ));

  /// Verifies the token by fetching the account, returning the account email.
  Future<String> verifyToken() async {
    final res = await _request(() => _dio.get('/account'), 'Verify token');
    _ensureOk(res, 'Verify token');
    return (res.data['account']?['email'] as String?) ?? 'DigitalOcean account';
  }

  /// Regions that can run the smallest droplet, as (slug, friendly name).
  Future<List<DoRegion>> regions() async {
    final res = await _request(() => _dio.get('/regions'), 'List regions');
    _ensureOk(res, 'List regions');
    final list = (res.data['regions'] as List?) ?? const [];
    return list
        .where((r) => (r['available'] as bool?) ?? false)
        .map((r) => DoRegion(r['slug'] as String, r['name'] as String))
        .toList();
  }

  /// Creates a droplet that auto-installs Lanway via cloud-init, pre-seeding
  /// [apiKey] so the Manager can connect without SSH. Returns the droplet id.
  Future<int> createDroplet({
    required String name,
    required String region,
    required String apiKey,
    String size = 's-1vcpu-1gb',
  }) async {
    final userData = _cloudInit(apiKey);
    final res = await _request(
      () => _dio.post('/droplets', data: jsonEncode({
        'name': name,
        'region': region,
        'size': size,
        'image': 'ubuntu-24-04-x64',
        'user_data': userData,
        'tags': ['lanway', 'lanway:$region'],
        'monitoring': true,
      })),
      'Create droplet',
    );
    _ensureOk(res, 'Create droplet');
    return res.data['droplet']['id'] as int;
  }

  /// Permanently destroys a droplet. Used when the operator deletes a server
  /// the Manager created, so they never have to open the cloud console. A 404
  /// is treated as success (already gone).
  Future<void> deleteDroplet(int dropletId) async {
    final res = await _request(() => _dio.delete('/droplets/$dropletId'), 'Delete server');
    final code = res.statusCode ?? 0;
    if (code != 204 && code != 202 && code != 404) {
      throw ApiException('Could not delete the server (HTTP $code). '
          'You can still delete it from your DigitalOcean dashboard.');
    }
  }

  /// Polls a droplet until it is active and has a public IPv4, returning the IP.
  /// A single failed poll (network blip) is tolerated; only a sustained failure
  /// over [maxAttempts] gives up.
  Future<String> waitForPublicIp(int dropletId, {int maxAttempts = 90}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final res = await _dio.get('/droplets/$dropletId');
        _ensureOk(res, 'Poll droplet');
        final droplet = res.data['droplet'];
        final status = droplet['status'] as String?;
        if (status == 'active') {
          final networks = (droplet['networks']?['v4'] as List?) ?? const [];
          for (final n in networks) {
            if (n['type'] == 'public') return n['ip_address'] as String;
          }
        }
      } on DioException {
        // transient connection blip — keep polling
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw ApiException('Timed out waiting for the server to come online');
  }

  /// Wraps a Dio call so network failures surface as friendly [ApiException]s
  /// instead of crashing the provisioning flow.
  Future<Response<dynamic>> _request(
      Future<Response<dynamic>> Function() call, String action) async {
    try {
      return await call();
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          throw ApiException('$action: cannot reach DigitalOcean — check your connection and try again.');
        default:
          throw ApiException('$action failed: ${e.message ?? e.type.name}');
      }
    }
  }

  /// cloud-init that installs Lanway and pre-seeds the access key + port.
  static String _cloudInit(String apiKey) {
    return '''#cloud-config
runcmd:
  - export LANWAY_API_KEY='$apiKey'
  - export LANWAY_PORT=8080
  - curl -fsSL https://get.lanway.org -o /root/install-lanway.sh
  - LANWAY_API_KEY='$apiKey' LANWAY_PORT=8080 bash /root/install-lanway.sh 2>&1 | tee /root/lanway-install.log
''';
  }

  void _ensureOk(Response res, String action) {
    final code = res.statusCode ?? 0;
    if (code >= 400) {
      final msg = res.data is Map && res.data['message'] is String
          ? res.data['message'] as String
          : '$action failed ($code)';
      throw ApiException(msg, statusCode: code);
    }
  }
}

/// Generates a URL-safe random access key for pre-seeding a new server.
String generateAccessKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
