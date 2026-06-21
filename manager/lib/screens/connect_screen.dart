import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/hover_card.dart';
import 'create_server_screen.dart';
import 'google_create_screen.dart';
import 'guided_setup_screen.dart';

/// Welcome / provider chooser. Four ways to stand up (or connect to) a server.
class ConnectScreen extends ConsumerWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doAccount = ref.watch(doAccountProvider);
    final servers = ref.watch(serversProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    LanwayLogo(size: 44),
                    SizedBox(width: 12),
                    LanwayWordmark(fontSize: 26),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Run a server, share freedom.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose where to host. Everything runs on your own account — Lanway '
                  'never sees your data.',
                  style: TextStyle(color: LanwayColors.mint, fontSize: 16),
                ),
                if (servers.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(servers.length == 1 ? 'Your server' : 'Your servers',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  for (final s in servers) ...[
                    _CurrentServerCard(server: s),
                    const SizedBox(height: 12),
                  ],
                  Text('Add another below.',
                      style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 13)),
                ],
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, c) {
                    final cards = <Widget>[
                      _DigitalOceanCard(account: doAccount),
                      const _GoogleCard(),
                      _GuidedProviderCard(
                        badge: 'FLEXIBLE',
                        assetIcon: 'assets/icons/aws.svg',
                        title: 'Amazon Web Services',
                        reasons: const [
                          '12 months free tier (Lightsail)',
                          'Widest choice of regions',
                          'Scales to any size later',
                        ],
                        providerName: 'AWS',
                        steps: const [
                          'In Amazon Lightsail, click Create instance → Linux/Unix → Ubuntu → '
                              'pick the cheapest plan → Create.',
                          'Open the instance → Networking tab → IPv4 Firewall → Add rule: allow '
                              'TCP 443, then add another rule for TCP 8080.',
                          '(Recommended) Attach a static IP on the Networking tab so the address '
                              'doesn’t change when the instance reboots.',
                          'Click "Connect using SSH" to open a terminal in the browser.',
                        ],
                      ),
                      _ManualCard(),
                    ];
                    if (c.maxWidth < 820) {
                      return Column(
                        children: [
                          for (final card in cards)
                            Padding(padding: const EdgeInsets.only(bottom: 20), child: card),
                        ],
                      );
                    }
                    // IntrinsicHeight gives the row a bounded height so the two
                    // cards stretch to match the taller one (without it, stretch
                    // inside a scroll view gets unbounded height and breaks).
                    Widget row(Widget a, Widget b) => IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: a),
                              const SizedBox(width: 20),
                              Expanded(child: b),
                            ],
                          ),
                        );
                    return Column(
                      children: [
                        row(cards[0], cards[1]),
                        const SizedBox(height: 20),
                        row(cards[2], cards[3]),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One saved server, with its name + platform and a shortcut to its dashboard.
class _CurrentServerCard extends ConsumerWidget {
  final ServerConnection server;
  const _CurrentServerCard({required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() {
      ref.read(serverStoreProvider.notifier).setActive(server);
      context.go('/dashboard');
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: open,
      child: Container(
        decoration: BoxDecoration(
          color: LanwayColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: LanwayColors.accent.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LanwayColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.dns, color: LanwayColors.accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 9, color: Color(0xFF3FB950)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(server.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${server.platformLabel}  ·  ${server.host}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6), fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Rename',
              onPressed: () => _renameServer(context, ref, server),
              icon: Icon(Icons.edit_outlined, size: 18, color: LanwayColors.mint.withValues(alpha: 0.8)),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: open, child: const Text('Open dashboard')),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a friendly server name and saves it.
Future<void> _renameServer(BuildContext context, WidgetRef ref, ServerConnection server) async {
  final controller = TextEditingController(text: server.name ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: LanwayColors.surface,
      title: const Text('Name this server'),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: server.host,
          helperText: '${server.platformLabel}  ·  ${server.host}',
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
      ],
    ),
  );
  if (name == null) return;
  await ref.read(serverStoreProvider.notifier).rename(server, name.trim());
}

class _CardScaffold extends StatelessWidget {
  final String badge;
  final Color badgeColor;
  final Widget icon;
  final String title;
  final List<String> reasons;
  final Widget footer;
  final Widget? menu; // optional 3-dots (e.g. Disconnect) when connected
  const _CardScaffold({
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.title,
    required this.reasons,
    required this.footer,
    this.menu,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Badge(label: badge, color: badgeColor),
            const Spacer(),
            icon,
            ?menu,
          ],
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: Colors.white)),
        const SizedBox(height: 14),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 18, color: LanwayColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r,
                      style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.75), height: 1.4)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        footer,
      ],
    );
  }
}

/// A small 3-dots menu offering "Disconnect" for a connected provider account.
Widget _disconnectMenu(BuildContext context,
    {required String provider, required String email, required VoidCallback onDisconnect}) {
  return PopupMenuButton<String>(
    icon: Icon(Icons.more_vert, size: 20, color: LanwayColors.mint.withValues(alpha: 0.6)),
    color: LanwayColors.surface,
    tooltip: 'Account',
    onSelected: (_) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: LanwayColors.surface,
          title: Text('Disconnect $provider account'),
          content: Text('$email will be removed from this app. Your servers keep running.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: LanwayColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      );
      if (yes == true) onDisconnect();
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'disconnect', child: Text('Disconnect account')),
    ],
  );
}

class _DigitalOceanCard extends ConsumerWidget {
  final DoAccount? account;
  const _DigitalOceanCard({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = account != null;
    return HoverCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreateServerScreen()),
      ),
      child: _CardScaffold(
        badge: connected ? 'CONNECTED' : 'RECOMMENDED',
        badgeColor: connected ? const Color(0xFF3FB950) : LanwayColors.accent,
        icon: SvgPicture.asset('assets/icons/digitalocean.svg', width: 30, height: 30),
        menu: connected
            ? _disconnectMenu(context,
                provider: 'DigitalOcean',
                email: account!.email,
                onDisconnect: () => ref.read(doAccountProvider.notifier).clear())
            : null,
        title: 'DigitalOcean',
        reasons: const [
          'True one-click — authorize in your browser, no terminal',
          'About \$6/month with 1 TB of transfer',
          'Your private server is ready in ~2 minutes',
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connected) ...[
              Row(
                children: [
                  const Icon(Icons.account_circle, size: 18, color: Color(0xFF3FB950)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Connected as ${account!.email}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF3FB950), fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateServerScreen()),
              ),
              icon: const Icon(Icons.bolt, size: 20),
              label: Text(connected ? 'Create a server' : 'Set up on DigitalOcean'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleCard extends ConsumerWidget {
  const _GoogleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(googleAccountProvider);
    final connected = account != null;
    void open() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GoogleCreateScreen()),
        );
    return HoverCard(
      onTap: open,
      child: _CardScaffold(
        badge: connected ? 'CONNECTED' : 'ONE-CLICK',
        badgeColor: connected ? const Color(0xFF3FB950) : LanwayColors.accent,
        icon: SvgPicture.asset('assets/icons/google_cloud.svg', width: 28, height: 28),
        menu: connected
            ? _disconnectMenu(context,
                provider: 'Google Cloud',
                email: account.email,
                onDisconnect: () => ref.read(googleAccountProvider.notifier).clear())
            : null,
        title: 'Google Cloud',
        reasons: const [
          'One-click — authorize in your browser, no terminal',
          'Free-tier e2-micro in US regions',
          'Creates a dedicated LanwayServer project',
        ],
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connected) ...[
              Row(
                children: [
                  const Icon(Icons.account_circle, size: 18, color: Color(0xFF3FB950)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Connected as ${account.email}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF3FB950), fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: open,
              icon: const Icon(Icons.bolt, size: 20),
              label: Text(connected ? 'Create a server' : 'Set up on Google Cloud'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidedProviderCard extends StatelessWidget {
  final String badge;
  final String assetIcon;
  final String title;
  final List<String> reasons;
  final String providerName;
  final List<String> steps;
  const _GuidedProviderCard({
    required this.badge,
    required this.assetIcon,
    required this.title,
    required this.reasons,
    required this.providerName,
    this.steps = const [],
  });

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GuidedSetupScreen(provider: providerName, steps: steps),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: () => _open(context),
      child: _CardScaffold(
        badge: badge,
        badgeColor: LanwayColors.primary,
        icon: SvgPicture.asset(assetIcon, width: 28, height: 28),
        title: title,
        reasons: reasons,
        footer: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: LanwayColors.mint,
            side: BorderSide(color: LanwayColors.mint.withValues(alpha: 0.3)),
            minimumSize: const Size(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _open(context),
          child: const Text('Set up'),
        ),
      ),
    );
  }
}

class _ManualCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return HoverCard(
      onTap: () => _openManual(context),
      child: _CardScaffold(
        badge: 'ANY SERVER',
        badgeColor: LanwayColors.primary,
        icon: Icon(Icons.terminal, color: LanwayColors.mint.withValues(alpha: 0.7), size: 24),
        title: 'Connect to a server',
        reasons: const [
          'Use any VPS — Vultr, Linode, Hetzner, or your own box',
          'One install command, then paste the address + key',
          'Full control, often the cheapest option',
        ],
        footer: FilledButton.icon(
          onPressed: () => _openManual(context),
          icon: const Icon(Icons.link, size: 20),
          label: const Text('Connect to a server'),
        ),
      ),
    );
  }

  void _openManual(BuildContext context) {
    showDialog<void>(context: context, builder: (_) => const _ManualConnectDialog());
  }
}

class _ManualConnectDialog extends ConsumerStatefulWidget {
  const _ManualConnectDialog();
  @override
  ConsumerState<_ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends ConsumerState<_ManualConnectDialog> {
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
    final conn = ServerConnection(baseUrl: _normalize(url), apiKey: key);
    try {
      final api = LanwayApiClient(conn);
      await api.stats();
      await ref.read(serverStoreProvider.notifier).add(conn.copyWith(certSha256: api.observedCertSha256));
      if (mounted) {
        Navigator.pop(context);
        context.go('/dashboard');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _installCmd = 'sudo bash <(curl -fsSL https://get.lanway.org)';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LanwayColors.surface,
      title: const Text('Connect to a server'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Step(
                num: '1',
                text: 'On your own Linux server (any VPS — or your own box), run this once:',
              ),
              const SizedBox(height: 10),
              _CommandBox(command: _installCmd),
              const SizedBox(height: 18),
              const _Step(
                num: '2',
                text: 'When it finishes, the installer prints a green box with your '
                    'Manager API URL and Access key. Paste them below.',
              ),
              const SizedBox(height: 8),
              _SampleOutput(),
              const SizedBox(height: 18),
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
            ],
          ),
        ),
      ),
      actions: [
        _ActionButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.pop(context)),
        _ActionButton(
          label: 'Connect',
          filled: true,
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
      ],
    );
  }
}

/// A numbered step heading inside the connect flow.
class _Step extends StatelessWidget {
  final String num;
  final String text;
  const _Step({required this.num, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LanwayColors.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Text(num,
              style: const TextStyle(
                  color: LanwayColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(text,
                style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.85), height: 1.4)),
          ),
        ),
      ],
    );
  }
}

/// A monospace command with a one-tap copy button.
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
            child: SelectableText(
              widget.command,
              style: const TextStyle(
                  color: LanwayColors.mint, fontFamily: 'monospace', fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: LanwayColors.accent),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.command));
              if (!mounted) return;
              setState(() => _copied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
        ],
      ),
    );
  }
}

/// A tiny preview of what the installer prints, so people recognise it.
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

/// Equal-height dialog action button (Cancel + confirm line up on hover).
class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Widget? child;
  const _ActionButton({required this.label, this.onPressed, this.filled = false, this.child});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const size = Size(96, 44);
    final content = child ?? Text(label);
    if (filled) {
      return FilledButton(
        style: FilledButton.styleFrom(minimumSize: size, shape: shape),
        onPressed: onPressed,
        child: content,
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
          minimumSize: size, shape: shape, foregroundColor: LanwayColors.mint),
      onPressed: onPressed,
      child: content,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5)),
    );
  }
}
