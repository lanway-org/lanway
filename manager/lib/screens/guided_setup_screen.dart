import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// Outline-style guided setup for providers without one-click (Google Cloud,
/// AWS, or any VPS): show provider-specific create + firewall steps, the install
/// command, then take the address + key the installer prints.
class GuidedSetupScreen extends ConsumerStatefulWidget {
  final String provider;
  final List<String> steps; // provider-specific "create the server" steps
  const GuidedSetupScreen({super.key, required this.provider, required this.steps});

  @override
  ConsumerState<GuidedSetupScreen> createState() => _GuidedSetupScreenState();
}

class _GuidedSetupScreenState extends ConsumerState<GuidedSetupScreen> {
  static const _installCmd = 'sudo bash <(curl -fsSL https://get.lanway.org)';
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  Future<void> _connect() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _error = 'Enter both the server address and access key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Tag the platform (e.g. 'aws') so Settings can show the right "delete it
    // yourself" guidance — we can't destroy a guided/manual instance over the API.
    final providerCode = widget.provider.toLowerCase() == 'aws' ? 'aws' : 'manual';
    final conn = ServerConnection(baseUrl: _normalize(url), apiKey: key, provider: providerCode);
    try {
      final api = LanwayApiClient(conn);
      await api.stats();
      await ref.read(serverStoreProvider.notifier).add(conn.copyWith(certSha256: api.observedCertSha256));
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepCount = widget.steps.length;
    return Scaffold(
      appBar: AppBar(title: Text('Set up on ${widget.provider}'), backgroundColor: LanwayColors.navy),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create a small Linux server, run one command, then paste what it '
                    'prints. Takes about 3 minutes.',
                    style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.75), height: 1.5)),
                const SizedBox(height: 24),
                // Provider-specific create + firewall steps.
                for (var i = 0; i < stepCount; i++)
                  _NumStep(num: '${i + 1}', text: widget.steps[i]),
                // Run the installer.
                _NumStep(num: '${stepCount + 1}', text: 'On the server, run this command:'),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: _CommandBox(command: _installCmd),
                ),
                const SizedBox(height: 18),
                // Paste the result.
                _NumStep(
                    num: '${stepCount + 2}',
                    text: 'It prints a green box with your Manager API URL and Access key — '
                        'paste them below.'),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SampleOutput(),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _urlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Server address / API URL',
                          hintText: 'https://1.2.3.4:8080',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyCtrl,
                        obscureText: true,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Access key',
                          hintText: 'The long key from the green box',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: _busy
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.link, size: 20),
                          label: const Text('Connect'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered step row.
class _NumStep extends StatelessWidget {
  final String num;
  final String text;
  const _NumStep({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LanwayColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(num,
                style: const TextStyle(
                    color: LanwayColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text,
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.85), height: 1.45)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Monospace command with a copy button.
class _CommandBox extends StatefulWidget {
  final String command;
  const _CommandBox({required this.command});
  @override
  State<_CommandBox> createState() => _CommandBoxState();
}

class _CommandBoxState extends State<_CommandBox> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF06101F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(widget.command,
                style: const TextStyle(
                    color: LanwayColors.mint, fontFamily: 'monospace', fontSize: 13, height: 1.4)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: LanwayColors.accent),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.command));
              if (!mounted) return;
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2),
                  () => mounted ? setState(() => _copied = false) : null);
            },
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
        ],
      ),
    );
  }
}

/// Green preview of what the installer prints.
class _SampleOutput extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FB950);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF06101F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: green.withValues(alpha: 0.35)),
      ),
      child: const DefaultTextStyle(
        style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.6, color: green),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✓  Lanway is running.'),
            Text('   Manager API URL :  https://1.2.3.4:8080'),
            Text('   Access key      :  Kx7pQ2…s9Vw  (long random string)'),
          ],
        ),
      ),
    );
  }
}
