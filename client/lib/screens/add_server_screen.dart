import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../storage.dart';
import '../theme.dart';
import '../vless.dart';

/// Add a server via QR scan, pasted link, or manual entry.
class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key});
  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> {
  Future<void> _save(String link, {String? name}) async {
    final parsed = parseShareLink(link);
    if (parsed == null) {
      _toast('That doesn’t look like a valid Lanway key.');
      return;
    }
    final server = await ref
        .read(serversProvider.notifier)
        .add(name?.trim().isNotEmpty == true ? name!.trim() : parsed.name, parsed.vless);
    await ref.read(activeServerIdProvider.notifier).set(server.id);
    if (mounted) context.go('/');
  }

  void _toast(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add a server'),
          backgroundColor: LanwayColors.navy,
          bottom: const TabBar(
            indicatorColor: LanwayColors.accent,
            labelColor: LanwayColors.accent,
            unselectedLabelColor: LanwayColors.mint,
            tabs: [
              Tab(text: 'Paste link'),
              Tab(text: 'Manual'),
              Tab(text: 'Scan QR'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PasteTab(onSave: _save),
            _ManualTab(onSave: (link, name) => _save(link, name: name)),
            _ScanTab(onDetect: _save),
          ],
        ),
      ),
    );
  }
}

class _ScanTab extends StatefulWidget {
  final void Function(String link) onDetect;
  const _ScanTab({required this.onDetect});
  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  bool _handled = false;
  int _attempt = 0; // bump to recreate the camera on retry

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          key: ValueKey(_attempt),
          errorBuilder: (context, error, child) => _ScanError(
            onRetry: () => setState(() {
              _attempt++;
              _handled = false;
            }),
          ),
          onDetect: (capture) {
            if (_handled) return;
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && parseShareLink(value) != null) {
                _handled = true;
                widget.onDetect(value);
                break;
              }
            }
          },
        ),
        // Viewfinder overlay.
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: LanwayColors.accent, width: 3),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        Positioned(
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: LanwayColors.navy.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Point at the QR code from the Manager app',
                style: TextStyle(color: LanwayColors.mint)),
          ),
        ),
      ],
    );
  }
}

/// Shown when the camera can't start (no permission, no camera, or it failed).
class _ScanError extends StatelessWidget {
  final VoidCallback onRetry;
  const _ScanError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined,
                size: 48, color: LanwayColors.mint.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('Camera unavailable',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Allow camera access, or use “Paste link” instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6))),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasteTab extends StatefulWidget {
  final void Function(String link) onSave;
  const _PasteTab({required this.onSave});
  @override
  State<_PasteTab> createState() => _PasteTabState();
}

class _PasteTabState extends State<_PasteTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text('Paste the vless:// or lanway:// key your server admin shared.',
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.65))),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'vless://…  or  lanway://add?config=…'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => widget.onSave(_ctrl.text),
            child: const Text('Add server'),
          ),
        ],
      ),
    );
  }
}

class _ManualTab extends StatefulWidget {
  final void Function(String link, String name) onSave;
  const _ManualTab({required this.onSave});
  @override
  State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab> {
  final _name = TextEditingController(text: 'My server');
  final _host = TextEditingController();
  final _port = TextEditingController(text: '443');
  final _uuid = TextEditingController();
  final _path = TextEditingController(text: '/vpn');
  bool _tls = false;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _uuid, _path]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final host = _host.text.trim();
    final uuid = _uuid.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 443;
    if (host.isEmpty || uuid.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Address and UUID are required.')));
      return;
    }
    final link = buildManualVless(
      uuid: uuid,
      host: host,
      port: port,
      name: _name.text.trim(),
      tls: _tls,
      path: _path.text.trim(),
    );
    widget.onSave(link, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _field('Name', _name),
        _field('Address', _host, hint: '1.2.3.4 or vpn.example.com'),
        _field('Port', _port, keyboard: TextInputType.number),
        _field('UUID', _uuid, hint: 'user id from the server'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _tls,
          onChanged: (v) => setState(() => _tls = v),
          title: const Text('Use TLS + WebSocket (own-domain mode)',
              style: TextStyle(color: LanwayColors.mint, fontSize: 14)),
          activeThumbColor: LanwayColors.accent,
        ),
        if (_tls) _field('WebSocket path', _path),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Add server')),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}
