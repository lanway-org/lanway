import 'package:flutter_test/flutter_test.dart';
import 'package:lanway_manager/models.dart';
import 'package:lanway_manager/providers.dart';

void main() {
  group('ServerConnection', () {
    const conn = ServerConnection(
      baseUrl: 'https://34.29.198.88:8080',
      apiKey: 'secret',
      provider: 'gcp',
    );

    test('host and hostPort parse from baseUrl', () {
      expect(conn.host, '34.29.198.88');
      expect(conn.hostPort, '34.29.198.88:8080');
    });

    test('displayName falls back to host, then uses the name', () {
      expect(conn.displayName, '34.29.198.88');
      expect(conn.copyWith(name: 'Singapore').displayName, 'Singapore');
      // Whitespace-only names are ignored.
      expect(conn.copyWith(name: '   ').displayName, '34.29.198.88');
    });

    test('platformLabel maps each provider', () {
      expect(conn.platformLabel, 'Google Cloud');
      expect(conn.copyWith().copyWith().platformLabel, 'Google Cloud');
      expect(const ServerConnection(baseUrl: 'https://x:8080', apiKey: 'k', provider: 'digitalocean').platformLabel,
          'DigitalOcean');
      expect(const ServerConnection(baseUrl: 'https://x:8080', apiKey: 'k', provider: 'aws').platformLabel, 'AWS');
      expect(const ServerConnection(baseUrl: 'https://x:8080', apiKey: 'k').platformLabel, 'Self-hosted');
    });

    test('copyWith preserves the pinned certificate unless overridden', () {
      final pinned = conn.copyWith(certSha256: 'abc123');
      expect(pinned.certSha256, 'abc123');
      // copyWith without the field keeps the existing pin.
      expect(pinned.copyWith(name: 'X').certSha256, 'abc123');
    });

    test('JSON round-trips every field including the pinned cert', () {
      final full = conn.copyWith(name: 'My Server', certSha256: 'deadbeef');
      final back = ServerConnection.fromJson(full.toJson());
      expect(back.baseUrl, full.baseUrl);
      expect(back.apiKey, full.apiKey);
      expect(back.provider, 'gcp');
      expect(back.name, 'My Server');
      expect(back.certSha256, 'deadbeef');
    });
  });

  group('ServerStore.active', () {
    const a = ServerConnection(baseUrl: 'https://1.1.1.1:8080', apiKey: 'k');
    const b = ServerConnection(baseUrl: 'https://2.2.2.2:8080', apiKey: 'k');

    test('returns null when empty', () {
      expect(const ServerStore().active, isNull);
    });

    test('returns the server matching activeUrl', () {
      const store = ServerStore(servers: [a, b], activeUrl: 'https://2.2.2.2:8080');
      expect(store.active, b);
    });

    test('falls back to the first server when activeUrl is unknown', () {
      const store = ServerStore(servers: [a, b], activeUrl: 'https://9.9.9.9:8080');
      expect(store.active, a);
    });
  });
}
