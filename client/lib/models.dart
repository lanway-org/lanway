import 'dart:convert';

/// A server the user has saved, identified by its original share link.
class SavedServer {
  final String id; // stable local id
  final String name; // display label
  final String link; // the vless:// link used to build the tunnel config

  const SavedServer({required this.id, required this.name, required this.link});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'link': link};

  factory SavedServer.fromJson(Map<String, dynamic> j) => SavedServer(
        id: j['id'] as String,
        name: j['name'] as String,
        link: j['link'] as String,
      );
}

/// Encodes/decodes the saved-server list for secure storage.
String encodeServers(List<SavedServer> servers) =>
    jsonEncode(servers.map((s) => s.toJson()).toList());

List<SavedServer> decodeServers(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final list = jsonDecode(raw) as List;
  return list.map((e) => SavedServer.fromJson(e as Map<String, dynamic>)).toList();
}
