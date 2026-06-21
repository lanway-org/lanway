import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// A selectable public DNS resolver used by the tunnel.
class DnsOption {
  final String name;
  final String primary;
  final String secondary;
  final String note;
  const DnsOption(this.name, this.primary, this.secondary, this.note);

  List<String> get servers =>
      [primary, secondary].where((s) => s.isNotEmpty).toList();
}

/// Built-in resolvers. An empty primary means "use the server's default".
const dnsOptions = <DnsOption>[
  DnsOption('Automatic', '', '', "Use the server's DNS"),
  DnsOption('Cloudflare', '1.1.1.1', '1.0.0.1', 'Fast, privacy-focused'),
  DnsOption('Google', '8.8.8.8', '8.8.4.4', 'Widely used and reliable'),
  DnsOption('Quad9', '9.9.9.9', '149.112.112.112', 'Blocks malicious domains'),
  DnsOption('OpenDNS Home', '208.67.222.222', '208.67.220.220', 'Optional filtering'),
  DnsOption('AdGuard', '94.140.14.14', '94.140.15.15', 'Blocks ads & trackers'),
  DnsOption('Control D', '76.76.2.0', '76.76.10.0', 'Customizable filtering'),
  DnsOption('CleanBrowsing Family', '185.228.168.168', '185.228.169.168', 'Family-friendly filtering'),
  DnsOption('Custom…', '', '', 'Enter your own DNS server'),
];

/// Persists the chosen DNS servers (comma-separated). Empty list = automatic.
class DnsNotifier extends StateNotifier<List<String>> {
  DnsNotifier() : super(const []) {
    _load();
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/dns.txt');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = (await f.readAsString()).trim();
        if (raw.isNotEmpty) state = raw.split(',').where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {/* ignore */}
  }

  Future<void> set(List<String> servers) async {
    state = servers;
    try {
      await (await _file()).writeAsString(servers.join(','), flush: true);
    } catch (_) {/* ignore */}
  }
}

final dnsServersProvider =
    StateNotifierProvider<DnsNotifier, List<String>>((ref) => DnsNotifier());
