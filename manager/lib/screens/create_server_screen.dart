import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../digitalocean.dart';
import '../do_oauth.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// One-click provisioning on DigitalOcean. The operator authorizes in the
/// browser, picks a region, and Lanway provisions + connects automatically. The
/// pre-seeded access key means we connect the moment the droplet's API answers.
class CreateServerScreen extends ConsumerStatefulWidget {
  const CreateServerScreen({super.key});
  @override
  ConsumerState<CreateServerScreen> createState() => _CreateServerScreenState();
}

enum _Step { connecting, region, provisioning, done }

class _CreateServerScreenState extends ConsumerState<CreateServerScreen> {
  _Step _step = _Step.connecting;
  bool _busy = false;
  bool _viaBrowser = true; // false when reusing a saved DigitalOcean token
  String? _error;
  int _stage = 0; // provisioning step index

  DigitalOceanClient? _client;
  List<DoRegion> _regions = const [];
  DoRegion? _region;

  @override
  void initState() {
    super.initState();
    // Kick off the browser authorize flow as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startOAuth());
  }

  /// Authorizes with DigitalOcean (reusing a saved token if present), captures
  /// the account email, and loads regions.
  Future<void> _startOAuth({bool forceReauth = false}) async {
    final existing = forceReauth ? null : ref.read(doAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
      _viaBrowser = existing == null;
    });
    try {
      final token = existing?.token ?? await DigitalOceanOAuth.authorize();
      final client = DigitalOceanClient(token);

      String email;
      try {
        email = await client.verifyToken();
      } on ApiException {
        // A saved token may have been revoked — clear it and re-authorize once.
        if (existing != null) {
          await ref.read(doAccountProvider.notifier).clear();
          if (mounted) await _startOAuth(forceReauth: true);
          return;
        }
        rethrow;
      }
      await ref.read(doAccountProvider.notifier).save(DoAccount(token: token, email: email));

      final regions = await client.regions();
      if (!mounted) return;
      setState(() {
        _client = client;
        _regions = regions;
        _region = regions.isNotEmpty ? regions.first : null;
        _step = _Step.region;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _provision() async {
    final client = _client;
    final region = _region;
    if (client == null || region == null) return;

    setState(() {
      _step = _Step.provisioning;
      _busy = true;
      _error = null;
      _stage = 0; // creating
    });

    final apiKey = generateAccessKey();
    final name = 'LanWay-${region.slug}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

    try {
      final id = await client.createDroplet(name: name, region: region.slug, apiKey: apiKey);

      if (mounted) setState(() => _stage = 1); // booting
      final ip = await client.waitForPublicIp(id);

      if (mounted) setState(() => _stage = 2); // installing
      final conn = ServerConnection(
        baseUrl: 'https://$ip:8080',
        apiKey: apiKey,
        provider: 'digitalocean',
        dropletId: id,
      );

      // The installer takes a couple of minutes; poll health until it answers.
      final fingerprint = await _pollHealth(conn);
      if (fingerprint == null) {
        throw ApiException('The server booted but Lanway did not come up in time. '
            'It may still be installing — try connecting in a few minutes with key:\n$apiKey');
      }

      if (mounted) setState(() => _stage = 3); // connecting
      await ref.read(serverStoreProvider.notifier).add(
          conn.copyWith(certSha256: fingerprint.isEmpty ? null : fingerprint));
      if (mounted) {
        setState(() {
          _stage = 4;
          _step = _Step.done;
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _step = _Step.region;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Polls until the server answers, then returns its TLS cert fingerprint (for
  /// pinning) — or null if it never came up.
  Future<String?> _pollHealth(ServerConnection conn) async {
    final api = LanwayApiClient(conn);
    for (var i = 0; i < 60; i++) {
      try {
        final h = await api.health();
        if (h.isOk) return api.observedCertSha256 ?? '';
      } catch (_) {
        // not up yet
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a server'),
        backgroundColor: LanwayColors.navy,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: switch (_step) {
              _Step.connecting => _connectingStep(),
              _Step.region => _regionStep(),
              _Step.provisioning => _provisioningStep(),
              _Step.done => _doneStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _connectingStep() {
    if (_error != null) {
      return Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.error_outline, color: LanwayColors.danger, size: 48),
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: LanwayColors.mint, height: 1.5)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _startOAuth, child: const Text('Try again')),
        ],
      );
    }
    return Column(
      children: [
        const SizedBox(height: 20),
        const SizedBox(
          height: 56,
          width: 56,
          child: CircularProgressIndicator(strokeWidth: 3, color: LanwayColors.accent),
        ),
        const SizedBox(height: 28),
        Text(_viaBrowser ? 'Waiting for DigitalOcean…' : 'Loading your account…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text(
          _viaBrowser
              ? 'A browser window opened for you to sign in and authorize Lanway. '
                  'Come back here once you approve.'
              : 'Fetching your DigitalOcean locations…',
          textAlign: TextAlign.center,
          style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6), height: 1.5),
        ),
        if (_viaBrowser) ...[
          const SizedBox(height: 24),
          TextButton(
            onPressed: _busy ? null : _startOAuth,
            child: const Text('Reopen the browser'),
          ),
        ],
      ],
    );
  }

  Widget _regionStep() {
    // One card per city (DigitalOcean may expose several datacenters per city).
    final byCity = <String, DoRegion>{};
    for (final r in _regions) {
      byCity.putIfAbsent(regionMeta(r.slug).city, () => r);
    }
    final cards = byCity.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose a location',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white)),
        const SizedBox(height: 8),
        const Text('This is where your internet will appear to come from. Pick one close '
            'to the people who will use it.',
            style: TextStyle(color: LanwayColors.mint, height: 1.4)),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final r in cards)
              _RegionCard(
                region: r,
                selected: _region?.slug == r.slug,
                onTap: () => setState(() => _region = r),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Smallest droplet · about \$6/month on your DigitalOcean account',
            style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.45), fontSize: 12)),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || _region == null) ? null : _provision,
            icon: const Icon(Icons.bolt, size: 20),
            label: const Text('Create server'),
          ),
        ),
      ],
    );
  }

  static const _stageLabels = [
    'Creating your server',
    'Booting up',
    'Installing Lanway',
    'Connecting',
  ];

  Widget _provisioningStep() {
    final total = _stageLabels.length;
    final fraction = (_stage / total).clamp(0.0, 1.0);
    final current = _stage < total ? _stageLabels[_stage] : 'Almost ready';

    return Column(
      children: [
        const SizedBox(height: 12),
        // Determinate radial progress with the percentage in the centre.
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: v <= 0 ? null : v, // indeterminate spin while creating
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0x1AFFFFFF),
                    valueColor: const AlwaysStoppedAnimation(LanwayColors.accent),
                  ),
                ),
              ),
              Text('${(fraction * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(current,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('This usually takes 2–3 minutes. Keep this window open.',
            textAlign: TextAlign.center,
            style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 13)),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < total; i++) _stepRow(_stageLabels[i], i),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepRow(String label, int i) {
    final done = i < _stage;
    final active = i == _stage;
    Widget leading;
    if (done) {
      leading = const Icon(Icons.check_circle, color: LanwayColors.accent, size: 22);
    } else if (active) {
      leading = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: LanwayColors.accent),
      );
    } else {
      leading = Icon(Icons.circle_outlined, color: LanwayColors.mint.withValues(alpha: 0.3), size: 20);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: leading)),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                color: done || active ? Colors.white : LanwayColors.mint.withValues(alpha: 0.45),
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                fontSize: 15,
              )),
        ],
      ),
    );
  }

  Widget _doneStep() {
    return Column(
      children: const [
        SizedBox(height: 20),
        Icon(Icons.check_circle, color: LanwayColors.accent, size: 64),
        SizedBox(height: 20),
        Text('Your server is live!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white)),
        SizedBox(height: 8),
        Text('Taking you to the dashboard…', style: TextStyle(color: LanwayColors.mint)),
      ],
    );
  }
}

/// A selectable location card showing a flag, city and country, with hover.
class _RegionCard extends StatefulWidget {
  final DoRegion region;
  final bool selected;
  final VoidCallback onTap;
  const _RegionCard({required this.region, required this.selected, required this.onTap});

  @override
  State<_RegionCard> createState() => _RegionCardState();
}

class _RegionCardState extends State<_RegionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final meta = regionMeta(widget.region.slug);
    final active = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 224,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          transform: _hover && !active
              ? (Matrix4.identity()..translateByDouble(0.0, -3.0, 0.0, 1.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: active || _hover ? const Color(0xFF13294A) : LanwayColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? LanwayColors.accent
                  : (_hover ? LanwayColors.accent.withValues(alpha: 0.6) : const Color(0x1AFFFFFF)),
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              meta.code.isEmpty
                  ? const Icon(Icons.public, size: 44, color: LanwayColors.accent)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        'assets/flags/${meta.code}.png',
                        width: 56,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.public, size: 44, color: LanwayColors.accent),
                      ),
                    ),
              const SizedBox(height: 12),
              Text(meta.city,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 16)),
              const SizedBox(height: 3),
              Text(meta.country.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: LanwayColors.mint.withValues(alpha: 0.5),
                      fontSize: 11,
                      letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
