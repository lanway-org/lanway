import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../digitalocean.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/donate.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: LanwayColors.navy),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _Section(
            title: 'Server connection',
            children: [
              _InfoRow(label: 'Manager API URL', value: conn?.baseUrl ?? '—'),
              _InfoRow(
                label: 'Access key',
                value: conn == null ? '—' : '•' * 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: LanwayColors.accent,
              side: BorderSide(color: LanwayColors.accent.withValues(alpha: 0.5)),
              minimumSize: const Size(0, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _EditConnectionDialog(current: conn),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit server address / key'),
          ),
          const SizedBox(height: 12),
          if (conn?.isManaged ?? false) ...[
            // Manager created this server, so we can destroy it for the user —
            // they'd otherwise have to hunt through their cloud console.
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: LanwayColors.danger,
                side: const BorderSide(color: LanwayColors.danger),
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _confirmDelete(context, ref, conn!),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete server'),
            ),
            const SizedBox(height: 8),
            Text(
              'This permanently destroys the DigitalOcean server and everything on it. '
              'Your users lose access immediately and this cannot be undone.',
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.45), fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _confirmForget(context, ref),
                style: TextButton.styleFrom(foregroundColor: LanwayColors.mint),
                child: const Text('Forget without deleting it'),
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: LanwayColors.danger,
                side: const BorderSide(color: LanwayColors.danger),
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: conn == null ? null : () => _confirmForget(context, ref),
              icon: const Icon(Icons.link_off),
              label: const Text('Forget this server'),
            ),
            const SizedBox(height: 8),
            Text(
              'Lanway only removes this server from the app — it keeps running and your '
              'users stay connected. Reconnect anytime with the same address and key. '
              'To stop paying, delete the instance in your cloud console '
              '(Google Cloud: Compute Engine → VM instances → select → Delete; '
              'AWS Lightsail: instance → ⋮ → Delete).',
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.45), fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 20),
          const DonateCard(),
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                const LanwayLogo(size: 40),
                const SizedBox(height: 10),
                const LanwayWordmark(fontSize: 18),
                const SizedBox(height: 6),
                Text('Free to use. Free to speak. Unlimited.',
                    style: TextStyle(
                        color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 13)),
                const SizedBox(height: 4),
                Text('lanway.org',
                    style: TextStyle(
                        color: LanwayColors.accent.withValues(alpha: 0.8), fontSize: 12)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.push('/license'),
                  child: const Text('License (MIT)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Destroys a Manager-created server (the cloud droplet itself), so the user
/// never has to open their DigitalOcean console. Falls back to a clear message
/// if the saved DO sign-in is gone.
Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ServerConnection conn) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => _NarrowDialog(
      title: 'Delete this server?',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This permanently destroys the DigitalOcean server and everything on it. '
            'Your users will lose access immediately. This cannot be undone.',
            style: TextStyle(height: 1.5),
          ),
          _serverIdentity(conn),
        ],
      ),
      actions: [
        _DialogButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        _DialogButton(
            label: 'Delete server',
            filled: true,
            danger: true,
            onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (yes != true) return;

  final account = ref.read(doAccountProvider);
  if (account == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sign in to DigitalOcean again to delete this server, '
            'or use “Forget without deleting it”.'),
      ));
    }
    return;
  }

  // Block with a small progress dialog while the droplet is destroyed.
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: LanwayColors.surface,
      content: Row(
        children: [
          SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
          SizedBox(width: 18),
          Text('Deleting your server…'),
        ],
      ),
    ),
  );

  try {
    await DigitalOceanClient(account.token).deleteDroplet(conn.dropletId!);
    await ref.read(serverStoreProvider.notifier).remove(conn);
    if (context.mounted) Navigator.pop(context); // close progress
    if (context.mounted) context.go('/connect');
  } on ApiException catch (e) {
    if (context.mounted) Navigator.pop(context); // close progress
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

Future<void> _confirmForget(BuildContext context, WidgetRef ref) async {
  final conn = ref.read(connectionProvider);
  if (conn == null) return;

  // For servers Lanway didn't create (Google Cloud / AWS / self-hosted) we can't
  // destroy the machine over the API, so first warn how to delete it by hand —
  // otherwise the user keeps getting billed. DigitalOcean is handled separately
  // by "Delete server", so its flow is unchanged.
  if (!conn.isManaged) {
    final proceed = await _deleteYourselfWarning(context, conn);
    if (proceed != true) return;
  }
  if (!context.mounted) return;

  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => _NarrowDialog(
      title: 'Forget this server?',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This only removes the server from this app. The server keeps running and '
            'your users stay connected. You can reconnect later with the same address and key.',
            style: TextStyle(height: 1.5),
          ),
          _serverIdentity(conn),
        ],
      ),
      actions: [
        _DialogButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        _DialogButton(
            label: 'Forget',
            filled: true,
            danger: true,
            onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (yes != true) return;
  await ref.read(serverStoreProvider.notifier).remove(conn);
  if (context.mounted) context.go('/connect');
}

/// Platform-specific reminder that the cloud instance must be deleted by hand
/// (Lanway only created DigitalOcean droplets — everything else is on the user).
Future<bool?> _deleteYourselfWarning(BuildContext context, ServerConnection conn) {
  final steps = switch (conn.provider) {
    'gcp' => 'Google Cloud Console → Compute Engine → VM instances → select your '
        'instance → Delete.',
    'aws' => 'AWS Lightsail → your instance → ⋮ → Delete  (or EC2 → Instances → '
        'Instance state → Terminate).',
    _ => 'Open your hosting provider’s console and delete or stop the server.',
  };
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _NarrowDialog(
      title: 'Delete it to stop paying',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lanway can’t delete a ${conn.platformLabel} server for you. Forgetting it here '
            'only removes it from the app — the instance keeps running and billing continues '
            'until you delete it yourself:',
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(steps, style: TextStyle(height: 1.5, color: LanwayColors.mint.withValues(alpha: 0.9))),
          _serverIdentity(conn),
        ],
      ),
      actions: [
        _DialogButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        _DialogButton(label: 'Continue', filled: true, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
}

/// AlertDialog with a constrained (narrower) width — the default stretches wide
/// on desktop.
class _NarrowDialog extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  const _NarrowDialog({required this.title, required this.body, required this.actions});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LanwayColors.surface,
      title: Text(title),
      content: SizedBox(width: 380, child: body),
      actions: actions,
    );
  }
}

/// Shows which server a dialog is about: name + platform + ip:port.
Widget _serverIdentity(ServerConnection conn) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: LanwayColors.navy, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.dns, size: 16, color: LanwayColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conn.displayName,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                Text('${conn.platformLabel}  ·  ${conn.hostPort}',
                    style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.7), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: LanwayColors.mint.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: LanwayColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6))),
          const Spacer(),
          Flexible(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Lets the operator change the server address (IP/URL) and access key, then
/// verifies the new details before saving.
class _EditConnectionDialog extends ConsumerStatefulWidget {
  final ServerConnection? current;
  const _EditConnectionDialog({required this.current});
  @override
  ConsumerState<_EditConnectionDialog> createState() => _EditConnectionDialogState();
}

class _EditConnectionDialogState extends ConsumerState<_EditConnectionDialog> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: widget.current?.baseUrl ?? '');
  late final TextEditingController _keyCtrl =
      TextEditingController(text: widget.current?.apiKey ?? '');
  bool _busy = false;
  bool _showKey = false;
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

  Future<void> _save() async {
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
    final conn = ServerConnection(baseUrl: _normalize(url), apiKey: key);
    try {
      final api = LanwayApiClient(conn);
      await api.stats(); // verify reachable + authorised
      await ref.read(serverStoreProvider.notifier).add(conn.copyWith(certSha256: api.observedCertSha256));
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LanwayColors.surface,
      title: const Text('Edit server connection', style: TextStyle(fontWeight: FontWeight.w500)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Server address / API URL',
                hintText: 'https://1.2.3.4:8080',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyCtrl,
              obscureText: !_showKey,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Access key',
                hintText: 'The long key printed by the installer',
                helperText: 'Tap the eye to reveal and check it. Paste the full key — it has no fixed length.',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility,
                      color: LanwayColors.mint.withValues(alpha: 0.6)),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        _DialogButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
        _DialogButton(
          label: 'Save',
          filled: true,
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
      ],
    );
  }
}

/// A dialog action button with a fixed height + shape, so Cancel and the
/// confirm button line up exactly (no hover-height mismatch).
class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;
  final Widget? child;
  const _DialogButton({
    required this.label,
    this.onPressed,
    this.filled = false,
    this.danger = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const size = Size(96, 44);
    final content = child ?? Text(label);
    if (filled) {
      return FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: size,
          shape: shape,
          backgroundColor: danger ? LanwayColors.danger : null,
        ),
        onPressed: onPressed,
        child: content,
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: size,
        shape: shape,
        foregroundColor: LanwayColors.mint,
      ),
      onPressed: onPressed,
      child: content,
    );
  }
}
