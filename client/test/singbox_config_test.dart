import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanway_client/singbox_config.dart';

void main() {
  group('buildSingBoxConfig', () {
    const link =
        'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBKEY123&sid=ab12&flow=xtls-rprx-vision&type=tcp#Lanway';

    late Map<String, dynamic> cfg;
    setUp(() => cfg = jsonDecode(buildSingBoxConfig(link)) as Map<String, dynamic>);

    test('has a TUN inbound that captures all traffic', () {
      final tun = (cfg['inbounds'] as List).single as Map<String, dynamic>;
      expect(tun['type'], 'tun');
      expect(tun['auto_route'], true);
      expect(tun['strict_route'], true);
      expect(tun['mtu'], 1400); // headroom for low-MTU links
    });

    test('builds a VLESS+REALITY outbound from the link', () {
      final proxy = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      expect(proxy['type'], 'vless');
      expect(proxy['server'], '1.2.3.4');
      expect(proxy['server_port'], 443);
      expect(proxy['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(proxy['flow'], 'xtls-rprx-vision');
      expect(proxy['packet_encoding'], 'xudp'); // carries UDP/QUIC

      final tls = proxy['tls'] as Map<String, dynamic>;
      expect(tls['server_name'], 'www.microsoft.com');
      expect((tls['reality'] as Map)['public_key'], 'PUBKEY123');
      expect((tls['reality'] as Map)['short_id'], 'ab12');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
    });

    test('routes DNS through the tunnel (no leak)', () {
      final server = ((cfg['dns'] as Map)['servers'] as List).first as Map<String, dynamic>;
      expect(server['detour'], 'proxy');
    });

    test('final route is the proxy', () {
      expect((cfg['route'] as Map)['final'], 'proxy');
    });

    test('TLS (websocket) mode also parses', () {
      const tlsLink = 'vless://uuid-1@host.example:8443?security=tls&type=ws&path=/vpn&sni=host.example#x';
      final c = jsonDecode(buildSingBoxConfig(tlsLink)) as Map<String, dynamic>;
      final proxy = (c['outbounds'] as List).first as Map<String, dynamic>;
      expect((proxy['tls'] as Map)['enabled'], true);
      expect((proxy['transport'] as Map)['type'], 'ws');
      expect((proxy['transport'] as Map)['path'], '/vpn');
    });
  });
}
