import 'dart:math';

import 'package:dio/dio.dart';

import 'api_client.dart';

/// A Google Cloud project the operator can deploy into.
class GcpProject {
  final String id;
  final String name;
  const GcpProject(this.id, this.name);
}

/// A Compute Engine zone, with its parent region for grouping.
class GcpZone {
  final String name; // e.g. us-central1-a
  final String region; // e.g. us-central1
  const GcpZone(this.name, this.region);
}

/// A Cloud Billing account that can fund a project.
class GcpBillingAccount {
  final String name; // e.g. billingAccounts/0X0X0X-...
  final String displayName;
  const GcpBillingAccount(this.name, this.displayName);
}

/// Free-tier-eligible regions for the e2-micro instance (Google's always-free
/// tier only applies in these US regions).
const gcpFreeTierRegions = {'us-west1', 'us-central1', 'us-east1'};

/// Minimal Google Cloud client used to provision a Lanway VM in one click. The
/// OAuth access token stays on this device and is sent only to googleapis.com.
class GoogleCloudClient {
  final Dio _dio;

  GoogleCloudClient(String token)
      : _dio = Dio(BaseOptions(
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (s) => s != null && s < 500,
        ));

  /// The signed-in account email.
  Future<String> verifyToken() async {
    final res = await _dio.get('https://openidconnect.googleapis.com/v1/userinfo');
    _ensureOk(res, 'Verify Google account');
    return (res.data['email'] as String?) ?? 'Google account';
  }

  /// Active projects the account can deploy into.
  Future<List<GcpProject>> projects() async {
    final res = await _dio.get('https://cloudresourcemanager.googleapis.com/v1/projects');
    _ensureOk(res, 'List projects');
    final list = (res.data['projects'] as List?) ?? const [];
    return list
        .where((p) => p['lifecycleState'] == 'ACTIVE')
        .map((p) => GcpProject(
              p['projectId'] as String,
              (p['name'] as String?) ?? p['projectId'] as String,
            ))
        .toList();
  }

  /// Finds the dedicated "LanwayServer" project, or creates one. We never touch
  /// the operator's other projects — a one-click mistake there could be costly.
  Future<GcpProject> findOrCreateLanwayProject() async {
    final existing = await projects();
    for (final p in existing) {
      if (p.name == 'LanwayServer' || p.id.startsWith('lanway-server')) return p;
    }
    final id = 'lanway-server-${_randomId(6)}';
    final res = await _dio.post(
      'https://cloudresourcemanager.googleapis.com/v1/projects',
      data: {'projectId': id, 'name': 'LanwayServer'},
    );
    _ensureOk(res, 'Create project');
    // projects.create is async — wait for the operation to finish.
    final opName = res.data is Map ? res.data['name'] as String? : null;
    if (opName != null) {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final op = await _dio.get('https://cloudresourcemanager.googleapis.com/v1/$opName');
        if (op.data is Map && op.data['done'] == true) break;
      }
    }
    return GcpProject(id, 'LanwayServer');
  }

  static String _randomId(int n) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Routes API quota/enablement checks to [projectId] (the project we own),
  /// instead of the OAuth client's project — which usually doesn't have the
  /// billing/compute APIs enabled and isn't ours to change.
  void useQuotaProject(String projectId) {
    _dio.options.headers['X-Goog-User-Project'] = projectId;
  }

  /// Stops routing quota to a specific project (back to the credentials' default
  /// quota project — the one that owns the OAuth client).
  void clearQuotaProject() {
    _dio.options.headers.remove('X-Goog-User-Project');
  }

  /// Enables a Google API on the project (like Outline does, so the operator
  /// doesn't have to do it by hand) and waits for it to take effect. [service]
  /// is e.g. "compute.googleapis.com" or "cloudbilling.googleapis.com".
  ///
  /// Just-created projects — and a quota project whose Service Usage was only
  /// just turned on — briefly return SERVICE_DISABLED (HTTP 403) while the
  /// change propagates, so we retry a few times before giving up.
  Future<void> enableApi(String project, String service) async {
    for (var attempt = 0;; attempt++) {
      final res = await _dio.post(
          'https://serviceusage.googleapis.com/v1/projects/$project/services/$service:enable');
      if ((res.statusCode ?? 0) == 403 && attempt < 5) {
        await Future<void>.delayed(const Duration(seconds: 5));
        continue;
      }
      _ensureOk(res, 'Enable $service');
      final data = res.data;
      if (data is Map && data['done'] == true) return;
      final opName = data is Map ? data['name'] as String? : null;
      if (opName == null) return;
      // Poll the long-running operation until enablement propagates (~30–60s).
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final op = await _dio.get('https://serviceusage.googleapis.com/v1/$opName');
        if (op.data is Map && op.data['done'] == true) return;
      }
      return;
    }
  }

  /// Whether the project has an active billing account (required for any VM —
  /// even free-tier e2-micro needs a billing account on file).
  Future<bool> billingEnabled(String project) async {
    final res =
        await _dio.get('https://cloudbilling.googleapis.com/v1/projects/$project/billingInfo');
    if ((res.statusCode ?? 0) >= 400) return false;
    return res.data is Map && res.data['billingEnabled'] == true;
  }

  /// Open billing accounts the operator can attach to a project. Throws on a
  /// real error (e.g. missing scope) so it isn't mistaken for "no accounts".
  Future<List<GcpBillingAccount>> billingAccounts() async {
    final res = await _dio.get('https://cloudbilling.googleapis.com/v1/billingAccounts');
    _ensureOk(res, 'List billing accounts');
    final list = (res.data['billingAccounts'] as List?) ?? const [];
    return list
        .where((b) => b['open'] == true)
        .map((b) => GcpBillingAccount(
            b['name'] as String, (b['displayName'] as String?) ?? b['name'] as String))
        .toList();
  }

  /// Attaches a billing account to the project.
  Future<void> linkBilling(String project, String billingAccountName) async {
    final res = await _dio.put(
      'https://cloudbilling.googleapis.com/v1/projects/$project/billingInfo',
      data: {'billingAccountName': billingAccountName},
    );
    _ensureOk(res, 'Link billing account');
  }

  /// Available (UP) zones in a project.
  Future<List<GcpZone>> zones(String project) async {
    final res = await _dio.get('https://compute.googleapis.com/compute/v1/projects/$project/zones');
    _ensureOk(res, 'List zones');
    final list = (res.data['items'] as List?) ?? const [];
    return list.where((z) => z['status'] == 'UP').map((z) {
      final name = z['name'] as String;
      final region = (z['region'] as String?)?.split('/').last ?? name;
      return GcpZone(name, region);
    }).toList();
  }

  /// Opens TCP 443 (VPN) + 8080 (manager API) on the default network for hosts
  /// tagged "lanway". Safe to call repeatedly (an existing rule is fine).
  Future<void> ensureFirewall(String project) async {
    final res = await _dio.post(
      'https://compute.googleapis.com/compute/v1/projects/$project/global/firewalls',
      data: {
        'name': 'lanway-allow',
        'network': 'global/networks/default',
        'direction': 'INGRESS',
        'allowed': [
          {'IPProtocol': 'tcp', 'ports': ['443', '8080']}
        ],
        'sourceRanges': ['0.0.0.0/0'],
        'targetTags': ['lanway'],
      },
    );
    final code = res.statusCode ?? 0;
    if (code == 409) return; // already exists
    _ensureOk(res, 'Open firewall');
  }

  /// Creates an e2-micro Ubuntu VM that auto-installs Lanway via a startup
  /// script, pre-seeding [apiKey]. Returns once the create request is accepted.
  Future<void> createInstance({
    required String project,
    required String zone,
    required String name,
    required String apiKey,
  }) async {
    final startup = '#!/bin/bash\n'
        "export LANWAY_API_KEY='$apiKey'\n"
        'export LANWAY_PORT=8080\n'
        'curl -fsSL https://get.lanway.org -o /root/install-lanway.sh\n'
        'bash /root/install-lanway.sh 2>&1 | tee /root/lanway-install.log\n';

    final res = await _dio.post(
      'https://compute.googleapis.com/compute/v1/projects/$project/zones/$zone/instances',
      data: {
        'name': name,
        'machineType': 'zones/$zone/machineTypes/e2-micro',
        'disks': [
          {
            'boot': true,
            'autoDelete': true,
            'initializeParams': {
              'sourceImage': 'projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts',
              'diskSizeGb': '10',
            },
          }
        ],
        'networkInterfaces': [
          {
            'network': 'global/networks/default',
            'accessConfigs': [
              {'type': 'ONE_TO_ONE_NAT', 'name': 'External NAT'}
            ],
          }
        ],
        'tags': {
          'items': ['lanway']
        },
        'metadata': {
          'items': [
            {'key': 'startup-script', 'value': startup}
          ]
        },
      },
    );
    _ensureOk(res, 'Create server');
  }

  /// Polls the instance until it has a public IPv4 and is RUNNING.
  Future<String> waitForExternalIp({
    required String project,
    required String zone,
    required String name,
    int maxAttempts = 60,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final res = await _dio.get(
            'https://compute.googleapis.com/compute/v1/projects/$project/zones/$zone/instances/$name');
        if ((res.statusCode ?? 0) < 300) {
          final nics = (res.data['networkInterfaces'] as List?) ?? const [];
          if (nics.isNotEmpty) {
            final acs = (nics[0]['accessConfigs'] as List?) ?? const [];
            if (acs.isNotEmpty && acs[0]['natIP'] != null) {
              return acs[0]['natIP'] as String;
            }
          }
        }
      } on DioException {
        // transient — keep polling
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw ApiException('Timed out waiting for the server to get an IP address.');
  }

  void _ensureOk(Response<dynamic> res, String action) {
    final code = res.statusCode ?? 0;
    if (code < 400) return;
    String msg = '$action failed (HTTP $code).';
    final data = res.data;
    if (data is Map && data['error'] is Map && data['error']['message'] is String) {
      msg = '$action: ${data['error']['message']}';
    }
    throw ApiException(msg, statusCode: code);
  }
}
