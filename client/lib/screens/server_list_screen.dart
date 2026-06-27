import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models.dart';
import '../storage.dart';
import '../theme.dart';
import '../vpn_controller.dart';

class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final activeId = ref.watch(activeServerIdProvider);
    final resolvedActive = ref.watch(activeServerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Servers'), backgroundColor: LanwayColors.navy),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: LanwayColors.accent,
        foregroundColor: LanwayColors.navy,
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: servers.isEmpty
          ? Center(
              child: Text('No servers saved yet.',
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6))),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: servers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final s = servers[i];
                final isActive = (activeId ?? resolvedActive?.id) == s.id;
                return _ServerTile(server: s, active: isActive);
              },
            ),
    );
  }
}

class _ServerTile extends ConsumerStatefulWidget {
  final SavedServer server;
  final bool active;
  const _ServerTile({required this.server, required this.active});
  @override
  ConsumerState<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends ConsumerState<_ServerTile> {
  int? _ping; // null = unknown, -1 = failed, >=0 = ms
  bool _pinging = false;

  Future<void> _measure() async {
    setState(() => _pinging = true);
    final ms = await ref.read(vpnControllerProvider.notifier).ping(widget.server);
    if (mounted) {
      setState(() {
        _ping = ms;
        _pinging = false;
      });
    }
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.server.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LanwayColors.surface,
        title: const Text('Rename server'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(hintText: _address),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      await ref.read(serversProvider.notifier).rename(widget.server.id, trimmed);
    }
  }

  Future<void> _confirmDelete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LanwayColors.surface,
        title: const Text('Delete this server?'),
        content: Text('“${widget.server.name}” ($_address) will be removed from this app.',
            style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LanwayColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(serversProvider.notifier).remove(widget.server.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.active ? LanwayColors.accent : const Color(0x14FFFFFF),
          width: widget.active ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () async {
          await ref.read(activeServerIdProvider.notifier).set(widget.server.id);
          if (context.mounted) context.pop();
        },
        leading: CircleAvatar(
          backgroundColor: LanwayColors.accent.withValues(alpha: 0.15),
          child: Icon(widget.active ? Icons.check : Icons.dns_outlined, color: LanwayColors.accent),
        ),
        title: Text(widget.server.name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(_address,
                style: TextStyle(
                    color: LanwayColors.mint.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontFamily: 'monospace')),
            const SizedBox(height: 2),
            _pingLabel(),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Test latency',
              onPressed: _pinging ? null : _measure,
              icon: _pinging
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed, color: LanwayColors.mint),
            ),
            IconButton(
              tooltip: 'Rename',
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined, color: LanwayColors.mint),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.white),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// The server's host:port, pulled from its vless link for display.
  String get _address {
    final m = RegExp(r'@([^/?#]+)').firstMatch(widget.server.link);
    return m?.group(1) ?? '—';
  }

  Widget _pingLabel() {
    if (_ping == null) {
      return Text('Tap the gauge to test latency',
          style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 12));
    }
    if (_ping! < 0) {
      return const Text('Unreachable', style: TextStyle(color: LanwayColors.danger, fontSize: 12));
    }
    final color = _ping! < 150 ? LanwayColors.accent : LanwayColors.amber;
    return Text('$_ping ms', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500));
  }
}
