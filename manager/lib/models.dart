// Data models mirroring the Lanway server REST API.

class ServerConnection {
  final String baseUrl; // e.g. https://1.2.3.4:8080
  final String apiKey;

  /// How this server was added: 'digitalocean' (one-click, we can destroy the
  /// droplet) or 'manual' (the user installed it themselves — we can only forget
  /// it locally). Other providers can be added later.
  final String provider;

  /// The cloud provider's machine id, when one-click created. Lets the Manager
  /// destroy the underlying server so the user doesn't have to find their cloud
  /// console. Null for manual connections.
  final int? dropletId;

  /// An optional operator-chosen label, so multiple servers are easy to tell
  /// apart. Falls back to the host when unset (see [displayName]).
  final String? name;

  /// SHA-256 of the server's TLS certificate (DER), pinned on first successful
  /// connect (trust-on-first-use). Later connections must present the same
  /// certificate, which stops a network attacker from intercepting the access
  /// key with a substituted certificate. Null = not yet pinned (legacy / first
  /// connect), in which case any certificate is accepted once to capture it.
  final String? certSha256;

  const ServerConnection({
    required this.baseUrl,
    required this.apiKey,
    this.provider = 'manual',
    this.dropletId,
    this.name,
    this.certSha256,
  });

  /// True when the Manager created this server and can delete it for the user.
  bool get isManaged => provider == 'digitalocean' && dropletId != null;

  /// The host (IP or domain) from [baseUrl], used as a default label.
  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  /// The host with its port, e.g. "34.29.198.88:8080".
  String get hostPort {
    final u = Uri.tryParse(baseUrl);
    if (u == null) return baseUrl;
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  /// What to show as the server's title — the custom name, or the host.
  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : host;

  /// Human-readable platform, shown as the subtitle.
  String get platformLabel => switch (provider) {
        'digitalocean' => 'DigitalOcean',
        'gcp' => 'Google Cloud',
        'aws' => 'AWS',
        _ => 'Self-hosted',
      };

  ServerConnection copyWith({String? name, String? certSha256}) => ServerConnection(
        baseUrl: baseUrl,
        apiKey: apiKey,
        provider: provider,
        dropletId: dropletId,
        name: name ?? this.name,
        certSha256: certSha256 ?? this.certSha256,
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'provider': provider,
        if (dropletId != null) 'dropletId': dropletId,
        if (name != null) 'name': name,
        if (certSha256 != null) 'certSha256': certSha256,
      };

  factory ServerConnection.fromJson(Map<String, dynamic> j) => ServerConnection(
        baseUrl: j['baseUrl'] as String,
        apiKey: j['apiKey'] as String,
        provider: j['provider'] as String? ?? 'manual',
        dropletId: (j['dropletId'] as num?)?.toInt(),
        name: j['name'] as String?,
        certSha256: j['certSha256'] as String?,
      );
}

class ServerHealth {
  final String status;
  final String mode;
  final String version;

  const ServerHealth({required this.status, required this.mode, required this.version});

  factory ServerHealth.fromJson(Map<String, dynamic> j) => ServerHealth(
        status: j['status'] as String? ?? 'unknown',
        mode: j['mode'] as String? ?? '',
        version: j['version'] as String? ?? '',
      );

  bool get isOk => status == 'ok';
}

class ServerStats {
  final int totalUsers;
  final int bandwidthBytes;
  final int uptimeSeconds;
  final String publicHost;
  final String mode;
  final int vpnPort;

  const ServerStats({
    required this.totalUsers,
    required this.bandwidthBytes,
    required this.uptimeSeconds,
    required this.publicHost,
    required this.mode,
    required this.vpnPort,
  });

  factory ServerStats.fromJson(Map<String, dynamic> j) => ServerStats(
        totalUsers: (j['total_users'] as num?)?.toInt() ?? 0,
        bandwidthBytes: (j['bandwidth_bytes'] as num?)?.toInt() ?? 0,
        uptimeSeconds: (j['uptime_seconds'] as num?)?.toInt() ?? 0,
        publicHost: j['public_host'] as String? ?? '',
        mode: j['mode'] as String? ?? '',
        vpnPort: (j['vpn_port'] as num?)?.toInt() ?? 443,
      );
}

class VpnUser {
  final String id;
  final String name;
  final double dataLimitGB; // 0 = unlimited
  final int usedBytes;
  final bool enabled;

  const VpnUser({
    required this.id,
    required this.name,
    required this.dataLimitGB,
    required this.usedBytes,
    required this.enabled,
  });

  factory VpnUser.fromJson(Map<String, dynamic> j) => VpnUser(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        dataLimitGB: (j['data_limit_gb'] as num?)?.toDouble() ?? 0,
        usedBytes: (j['used_bytes'] as num?)?.toInt() ?? 0,
        enabled: j['enabled'] as bool? ?? true,
      );

  bool get unlimited => dataLimitGB <= 0;

  /// Fraction of the data limit used, clamped to [0, 1]. Unlimited users
  /// report 0 so the bar stays empty.
  double get usageFraction {
    if (unlimited) return 0;
    final limit = dataLimitGB * 1024 * 1024 * 1024;
    if (limit <= 0) return 0;
    return (usedBytes / limit).clamp(0.0, 1.0);
  }
}

class ShareLinks {
  final String vless;
  final String lanway;
  final String label;

  const ShareLinks({required this.vless, required this.lanway, required this.label});

  factory ShareLinks.fromJson(Map<String, dynamic> j) => ShareLinks(
        vless: j['vless'] as String? ?? '',
        lanway: j['lanway'] as String? ?? '',
        label: j['label'] as String? ?? 'Lanway',
      );
}

class UserWithLinks {
  final VpnUser user;
  final ShareLinks links;
  const UserWithLinks({required this.user, required this.links});

  factory UserWithLinks.fromJson(Map<String, dynamic> j) => UserWithLinks(
        user: VpnUser.fromJson(j['user'] as Map<String, dynamic>),
        links: ShareLinks.fromJson(j['links'] as Map<String, dynamic>),
      );
}

/// Formats a byte count as a human-readable string (e.g. "1.4 GB").
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final fixed = value >= 100 || unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$fixed ${units[unit]}';
}

/// Formats an uptime in seconds as "3d 4h" / "5h 12m" / "42m".
String formatUptime(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
