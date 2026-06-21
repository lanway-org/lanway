import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';

/// All the operator's saved servers plus which one the dashboard is currently
/// showing. Everything lives only on this device — nothing is stored remotely.
class ServerStore {
  final List<ServerConnection> servers;
  final String? activeUrl;
  const ServerStore({this.servers = const [], this.activeUrl});

  /// The server the dashboard currently targets (defaults to the first).
  ServerConnection? get active {
    for (final s in servers) {
      if (s.baseUrl == activeUrl) return s;
    }
    return servers.isEmpty ? null : servers.first;
  }
}

class ServerStoreNotifier extends StateNotifier<ServerStore> {
  ServerStoreNotifier() : super(const ServerStore()) {
    _load();
  }

  static const _listKey = 'lanway.servers';
  static const _activeKey = 'lanway.active';
  static const _legacyKey = 'lanway.connection'; // single connection (old builds)

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var servers = <ServerConnection>[];
    final raw = prefs.getString(_listKey);
    if (raw != null) {
      servers = (jsonDecode(raw) as List)
          .map((e) => ServerConnection.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Migrate a single connection saved by an older build into the list.
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null) {
        servers = [ServerConnection.fromJson(jsonDecode(legacy) as Map<String, dynamic>)];
        await prefs.setString(_listKey, jsonEncode([for (final s in servers) s.toJson()]));
      }
    }
    state = ServerStore(servers: servers, activeUrl: prefs.getString(_activeKey));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listKey, jsonEncode([for (final s in state.servers) s.toJson()]));
    final active = state.activeUrl;
    active == null ? await prefs.remove(_activeKey) : await prefs.setString(_activeKey, active);
  }

  /// Adds a server (replacing any with the same address) and opens it.
  Future<void> add(ServerConnection conn) async {
    final list = [for (final s in state.servers) if (s.baseUrl != conn.baseUrl) s, conn];
    state = ServerStore(servers: list, activeUrl: conn.baseUrl);
    await _persist();
  }

  /// Makes [conn] the server the dashboard shows.
  Future<void> setActive(ServerConnection conn) async {
    state = ServerStore(servers: state.servers, activeUrl: conn.baseUrl);
    await _persist();
  }

  /// Sets a friendly label so multiple servers are easy to tell apart.
  Future<void> rename(ServerConnection conn, String name) async {
    final list = [
      for (final s in state.servers)
        if (s.baseUrl == conn.baseUrl) s.copyWith(name: name) else s
    ];
    state = ServerStore(servers: list, activeUrl: state.activeUrl);
    await _persist();
  }

  /// Forgets a server locally (does not touch the running machine).
  Future<void> remove(ServerConnection conn) async {
    final list = [for (final s in state.servers) if (s.baseUrl != conn.baseUrl) s];
    final active = state.activeUrl == conn.baseUrl ? null : state.activeUrl;
    state = ServerStore(servers: list, activeUrl: active);
    await _persist();
  }
}

final serverStoreProvider =
    StateNotifierProvider<ServerStoreNotifier, ServerStore>((ref) => ServerStoreNotifier());

/// Every saved server, in the order they were added.
final serversProvider = Provider<List<ServerConnection>>((ref) => ref.watch(serverStoreProvider).servers);

/// The server the dashboard currently targets. Null when none are saved.
final connectionProvider = Provider<ServerConnection?>((ref) => ref.watch(serverStoreProvider).active);

/// API client bound to the active connection. Null when not connected.
final apiClientProvider = Provider<LanwayApiClient?>((ref) {
  final conn = ref.watch(connectionProvider);
  if (conn == null) return null;
  return LanwayApiClient(conn);
});

/// Server stats, auto-refreshing. Throws if not connected.
final statsProvider = FutureProvider.autoDispose<ServerStats>((ref) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw ApiException('Not connected');
  return client.stats();
});

/// The user list, refreshable.
final usersProvider = FutureProvider.autoDispose<List<VpnUser>>((ref) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw ApiException('Not connected');
  return client.listUsers();
});

/// A signed-in DigitalOcean account, remembered so the operator doesn't have to
/// re-authorize and so the chooser can show the connected account email.
class DoAccount {
  final String token;
  final String email;
  const DoAccount({required this.token, required this.email});

  Map<String, dynamic> toJson() => {'token': token, 'email': email};
  factory DoAccount.fromJson(Map<String, dynamic> j) =>
      DoAccount(token: j['token'] as String, email: j['email'] as String);
}

class DoAccountNotifier extends StateNotifier<DoAccount?> {
  DoAccountNotifier() : super(null) {
    _load();
  }
  static const _prefsKey = 'lanway.do_account';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      state = DoAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  Future<void> save(DoAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(account.toJson()));
    state = account;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    state = null;
  }
}

final doAccountProvider =
    StateNotifierProvider<DoAccountNotifier, DoAccount?>((ref) => DoAccountNotifier());

/// Bump whenever the requested Google OAuth scopes change. A saved account from
/// an older scope set is auto-discarded so the operator re-consents and the new
/// scopes (e.g. cloud-billing) actually take effect.
const googleScopesVersion = 3;

/// A signed-in Google Cloud account. We keep the refresh token so the operator
/// stays connected (silent re-auth) and can disconnect later.
class GoogleAccount {
  final String email;
  final String refreshToken;
  final int scopesVersion;
  const GoogleAccount({
    required this.email,
    required this.refreshToken,
    this.scopesVersion = googleScopesVersion,
  });

  Map<String, dynamic> toJson() =>
      {'email': email, 'refreshToken': refreshToken, 'scopesVersion': scopesVersion};
  factory GoogleAccount.fromJson(Map<String, dynamic> j) => GoogleAccount(
        email: j['email'] as String,
        refreshToken: j['refreshToken'] as String,
        scopesVersion: (j['scopesVersion'] as num?)?.toInt() ?? 0,
      );
}

class GoogleAccountNotifier extends StateNotifier<GoogleAccount?> {
  GoogleAccountNotifier() : super(null) {
    _load();
  }
  static const _prefsKey = 'lanway.google_account';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final account = GoogleAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    // Discard a login granted under older scopes — force a fresh consent.
    if (account.scopesVersion != googleScopesVersion) {
      await prefs.remove(_prefsKey);
      return;
    }
    state = account;
  }

  Future<void> save(GoogleAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(account.toJson()));
    state = account;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    state = null;
  }
}

final googleAccountProvider =
    StateNotifierProvider<GoogleAccountNotifier, GoogleAccount?>((ref) => GoogleAccountNotifier());
