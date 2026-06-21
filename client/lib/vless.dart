import 'dart:convert';

import 'package:flutter_vless/flutter_vless.dart';

/// Builds the final Xray client config JSON from a vless link, optionally
/// pinning DNS servers and adding a local HTTP proxy inbound (desktop).
String buildClientConfig(String vlessLink, {List<String> dns = const [], bool httpInbound = false}) {
  final parsed = FlutterVless.parseFromURL(vlessLink);
  final config = jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;
  if (dns.isNotEmpty) {
    config['dns'] = {'servers': dns};
  }
  if (httpInbound) {
    (config['inbounds'] as List).add({
      'tag': 'http-in',
      'listen': '127.0.0.1',
      'port': 1081,
      'protocol': 'http',
      'settings': {'auth': 'noauth', 'udp': false},
    });
  }
  return const JsonEncoder.withIndent('  ').convert(config);
}

/// Result of normalising a pasted/scanned link into something the tunnel can use.
class ParsedLink {
  final String vless; // the underlying vless:// link
  final String name; // display name
  const ParsedLink({required this.vless, required this.name});
}

/// Normalises either a standard `vless://` link or a branded
/// `lanway://add?config=<urlencoded vless>&name=<label>` deep link into a
/// plain `vless://` link plus a display name.
///
/// Returns null if the input is not a link we understand.
ParsedLink? parseShareLink(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('lanway://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final config = uri.queryParameters['config'];
    if (config == null || !config.startsWith('vless://')) return null;
    final name = uri.queryParameters['name'] ?? _remarkOf(config);
    return ParsedLink(vless: config, name: name.isEmpty ? 'Lanway' : name);
  }

  if (trimmed.startsWith('vless://')) {
    return ParsedLink(vless: trimmed, name: _remarkOf(trimmed));
  }

  return null;
}

/// Extracts the fragment (#remark) of a vless link as its display name.
String _remarkOf(String vless) {
  final hash = vless.indexOf('#');
  if (hash < 0 || hash + 1 >= vless.length) return 'Lanway';
  return Uri.decodeComponent(vless.substring(hash + 1));
}

/// Builds a manual `vless://` link from individual REALITY/TLS fields entered
/// on the manual tab of the add-server screen.
String buildManualVless({
  required String uuid,
  required String host,
  required int port,
  required String name,
  required bool tls,
  String path = '/vpn',
}) {
  final query = <String, String>{
    'encryption': 'none',
    'type': tls ? 'ws' : 'tcp',
    'security': tls ? 'tls' : 'none',
  };
  if (tls) {
    query['path'] = path;
    query['sni'] = host;
  }
  final q = query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  return 'vless://$uuid@$host:$port?$q#${Uri.encodeComponent(name)}';
}

/// Parses a vless link into the flutter_vless URL object used to start the
/// tunnel. Throws [FormatException] for malformed links.
FlutterVlessURL toVlessURL(String vless) => FlutterVless.parseFromURL(vless);
