import 'dart:convert';

/// Builds a sing-box configuration that runs a full **TUN** tunnel on desktop:
/// a virtual interface captures *all* traffic (TCP **and UDP/QUIC**) and routes
/// it through a VLESS + REALITY outbound to the Lanway server. This is what makes
/// apps like Messenger work — unlike a SOCKS system proxy, nothing leaks around
/// the tunnel (QUIC included), so traffic can't fall back to the censored path.
///
/// The outbound is parsed from the same `vless://` link the rest of the app uses,
/// so the server side is unchanged.
String buildSingBoxConfig(String vlessLink, {List<String> dns = const ['1.1.1.1']}) {
  final dnsServer = dns.isNotEmpty ? dns.first : '1.1.1.1';

  final config = <String, dynamic>{
    'log': {'level': 'warn', 'timestamp': true},
    'dns': {
      // Resolve through the tunnel so DNS can't leak to the local (censored)
      // resolver.
      'servers': [
        {'tag': 'remote', 'address': dnsServer, 'detour': 'proxy'},
      ],
      'strategy': 'ipv4_only',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        // No interface_name: macOS requires the auto-assigned utunN naming.
        'address': ['172.19.0.1/30'],
        // 1400 leaves headroom for VLESS+TLS overhead on low-MTU links (your
        // connection caps at 1488), so large responses don't get dropped.
        'mtu': 1400,
        'auto_route': true,
        'strict_route': true,
        'stack': 'gvisor',
        'sniff': true,
      },
    ],
    'outbounds': [
      _vlessOutbound(vlessLink),
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {
      // Keep LAN/local traffic on the local network (don't tunnel it — the
      // server blackholes private IPs, which would otherwise break local
      // devices and spam EOF errors). Everything else goes through the tunnel.
      'rules': [
        {'ip_is_private': true, 'outbound': 'direct'},
      ],
      // auto_route adds the route to the server's IP via the real gateway, so
      // the encrypted tunnel itself doesn't loop back through the TUN.
      'auto_detect_interface': true,
      'final': 'proxy',
    },
  };

  return const JsonEncoder.withIndent('  ').convert(config);
}

/// Translates a `vless://` link into a sing-box VLESS outbound (REALITY or TLS).
Map<String, dynamic> _vlessOutbound(String vlessLink) {
  final uri = Uri.parse(vlessLink.trim());
  final q = uri.queryParameters;
  final security = q['security'] ?? 'none';

  final out = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': uri.host,
    'server_port': uri.hasPort ? uri.port : 443,
    'uuid': uri.userInfo,
    // xudp carries UDP (QUIC) over the VLESS stream — the whole point of TUN mode.
    'packet_encoding': 'xudp',
  };

  final flow = q['flow'] ?? '';
  if (flow.isNotEmpty) out['flow'] = flow;

  if (security == 'reality') {
    out['tls'] = {
      'enabled': true,
      'server_name': q['sni'] ?? uri.host,
      'utls': {'enabled': true, 'fingerprint': q['fp']?.isNotEmpty == true ? q['fp'] : 'chrome'},
      'reality': {
        'enabled': true,
        'public_key': q['pbk'] ?? '',
        'short_id': q['sid'] ?? '',
      },
    };
  } else if (security == 'tls') {
    out['tls'] = {'enabled': true, 'server_name': q['sni'] ?? uri.host};
    if ((q['type'] ?? '') == 'ws') {
      out['transport'] = {'type': 'ws', 'path': q['path'] ?? '/'};
    }
  }

  return out;
}
