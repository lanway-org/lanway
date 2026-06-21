import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// File-backed storage in the app-support directory. Works on every platform
/// without special entitlements, and (unlike keychain on unsigned macOS builds)
/// reliably persists across restarts. The data is the user's own VPN configs.
class _Store {
  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$name');
  }

  static Future<String?> read(String name) async {
    try {
      final f = await _file(name);
      if (await f.exists()) return await f.readAsString();
    } catch (_) {/* ignore */}
    return null;
  }

  static Future<void> write(String name, String value) async {
    try {
      final f = await _file(name);
      await f.writeAsString(value, flush: true);
    } catch (_) {/* ignore */}
  }

  static Future<void> delete(String name) async {
    try {
      final f = await _file(name);
      if (await f.exists()) await f.delete();
    } catch (_) {/* ignore */}
  }
}

const _serversFile = 'servers.json';
const _activeFile = 'active.txt';

/// Persists the saved-server list. Nothing is ever sent off the device.
class ServersNotifier extends StateNotifier<List<SavedServer>> {
  ServersNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    state = decodeServers(await _Store.read(_serversFile));
  }

  Future<void> _persist() async {
    await _Store.write(_serversFile, encodeServers(state));
  }

  /// Adds a server and returns it. Replaces any existing server with the same link.
  Future<SavedServer> add(String name, String link) async {
    final server = SavedServer(id: _randomId(), name: name, link: link);
    state = [...state.where((s) => s.link != link), server];
    await _persist();
    return server;
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  static String _randomId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

final serversProvider =
    StateNotifierProvider<ServersNotifier, List<SavedServer>>((ref) => ServersNotifier());

/// The id of the active server, persisted across launches.
class ActiveServerNotifier extends StateNotifier<String?> {
  ActiveServerNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final v = await _Store.read(_activeFile);
    if (v != null && v.isNotEmpty) state = v;
  }

  Future<void> set(String? id) async {
    state = id;
    if (id == null) {
      await _Store.delete(_activeFile);
    } else {
      await _Store.write(_activeFile, id);
    }
  }
}

final activeServerIdProvider =
    StateNotifierProvider<ActiveServerNotifier, String?>((ref) => ActiveServerNotifier());

/// The resolved active server object (first saved server if none chosen).
final activeServerProvider = Provider<SavedServer?>((ref) {
  final servers = ref.watch(serversProvider);
  if (servers.isEmpty) return null;
  final id = ref.watch(activeServerIdProvider);
  return servers.firstWhere((s) => s.id == id, orElse: () => servers.first);
});
