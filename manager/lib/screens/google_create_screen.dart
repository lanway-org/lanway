import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../digitalocean.dart' show generateAccessKey;
import '../google_oauth.dart';
import '../googlecloud.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// One-click provisioning on Google Cloud: browser sign-in, pick a project +
/// zone, then Lanway creates an e2-micro VM and connects automatically.
class GoogleCreateScreen extends ConsumerStatefulWidget {
  const GoogleCreateScreen({super.key});
  @override
  ConsumerState<GoogleCreateScreen> createState() => _GoogleCreateScreenState();
}

enum _Step { connecting, choose, provisioning, done }

class _GoogleCreateScreenState extends ConsumerState<GoogleCreateScreen> {
  _Step _step = _Step.connecting;
  bool _busy = false;
  String? _error;
  int _stage = 0;

  GoogleCloudClient? _client;
  GcpProject? _project;
  String? _email; // the signed-in Google account
  bool _viaBrowser = true; // false when a saved account is silently refreshed
  List<GcpZone> _zones = const [];
  GcpZone? _zone;
  String? _zonesError; // non-fatal API error while loading zones
  bool _needsBilling = false; // project has no billing account
  String _status = ''; // sub-status while preparing the project

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startOAuth());
  }

  Future<void> _startOAuth({bool forceReauth = false}) async {
    final saved = forceReauth ? null : ref.read(googleAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
      _step = _Step.connecting;
      _viaBrowser = saved == null;
      _status = '';
    });
    try {
      final String accessToken;
      final String email;
      if (saved != null) {
        try {
          accessToken = await GoogleOAuth.refresh(saved.refreshToken);
          email = saved.email;
        } on ApiException {
          // Saved token revoked — clear and re-authorize once in the browser.
          await ref.read(googleAccountProvider.notifier).clear();
          if (mounted) await _startOAuth(forceReauth: true);
          return;
        }
      } else {
        final tokens = await GoogleOAuth.authorize();
        email = await GoogleCloudClient(tokens.accessToken).verifyToken();
        if (tokens.refreshToken != null) {
          await ref
              .read(googleAccountProvider.notifier)
              .save(GoogleAccount(email: email, refreshToken: tokens.refreshToken!));
        }
        accessToken = tokens.accessToken;
      }

      final client = GoogleCloudClient(accessToken);
      if (!mounted) return;
      setState(() {
        _client = client;
        _email = email;
        _status = 'Setting up your LanwayServer project…';
      });
      // Use (or create) a dedicated project so we never touch the operator's own.
      final project = await client.findOrCreateLanwayProject();
      if (!mounted) return;
      setState(() {
        _project = project;
        _step = _Step.choose;
      });
      await _prepareProject(); // enable Compute API + billing, then zones
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Couldn’t reach Google. Check your internet connection '
            '(if the Lanway VPN is connected, disconnect it and retry).');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Drops the saved login and re-authorizes, so the operator can pick a
  /// different Google account (e.g. the one that owns their billing).
  Future<void> _switchAccount() async {
    await ref.read(googleAccountProvider.notifier).clear();
    await _startOAuth(forceReauth: true);
  }

  /// A zone row with its country flag — like DigitalOcean/Outline region pickers.
  Widget _zoneRow(GcpZone z) {
    final iso = _flagIso(z.region);
    final free = gcpFreeTierRegions.contains(z.region);
    return Row(
      children: [
        if (iso != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.asset('assets/flags/$iso.png',
                width: 22, height: 16, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 22)),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(free ? '${z.name}  ·  free tier' : z.name, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  GcpZone _defaultZone(List<GcpZone> zones) {
    for (final z in zones) {
      if (z.name == 'us-central1-a') return z;
    }
    for (final z in zones) {
      if (gcpFreeTierRegions.contains(z.region)) return z;
    }
    return zones.first;
  }

  /// Prepares the selected project Outline-style: enable the Compute Engine API,
  /// ensure billing (auto-link an existing account, else prompt), load zones.
  Future<void> _prepareProject() async {
    final client = _client;
    final project = _project;
    if (client == null || project == null) return;
    setState(() {
      _busy = true;
      _zonesError = null;
      _needsBilling = false;
      _zones = const [];
      _zone = null;
      _status = 'Preparing project…';
    });
    try {
      // Bootstrap: turn on Service Usage for our freshly-created project. This
      // first call uses the credentials' default quota project (the OAuth
      // client's project, which already has Service Usage) — our new project
      // doesn't have it yet, so nothing billed to it would work until now.
      client.clearQuotaProject();
      setState(() => _status = 'Preparing project…');
      await client.enableApi(project.id, 'serviceusage.googleapis.com');

      // Now our project can self-serve API enablement — bill quota to it and
      // enable the Cloud Billing API so we can read/link billing. (Enabling
      // this API doesn't need billing.)
      client.useQuotaProject(project.id);
      setState(() => _status = 'Enabling billing API…');
      await client.enableApi(project.id, 'cloudbilling.googleapis.com');

      // Billing next — enabling Compute Engine requires a billing account.
      if (!mounted) return;
      setState(() => _status = 'Checking billing…');
      var billed = await client.billingEnabled(project.id);
      if (!billed) {
        final accounts = await client.billingAccounts();
        if (accounts.isNotEmpty) {
          // Auto-link an existing account (no manual step), like Outline.
          await client.linkBilling(project.id, accounts.first.name);
          billed = await client.billingEnabled(project.id);
        }
      }
      if (!billed) {
        if (mounted) setState(() => _needsBilling = true);
        return;
      }

      if (!mounted) return;
      setState(() => _status = 'Enabling Compute Engine…');
      await client.enableApi(project.id, 'compute.googleapis.com');

      if (!mounted) return;
      setState(() => _status = 'Loading regions…');
      final zones = await client.zones(project.id);
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _zone = zones.isEmpty ? null : _defaultZone(zones);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _zonesError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _zonesError = 'Couldn’t reach Google. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _provision() async {
    final client = _client;
    final project = _project;
    final zone = _zone;
    if (client == null || project == null || zone == null) return;

    setState(() {
      _step = _Step.provisioning;
      _busy = true;
      _error = null;
      _stage = 0;
    });

    final apiKey = generateAccessKey();
    final name = 'lanway-${zone.region}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

    try {
      await client.ensureFirewall(project.id);
      await client.createInstance(
          project: project.id, zone: zone.name, name: name, apiKey: apiKey);

      if (mounted) setState(() => _stage = 1); // booting
      final ip = await client.waitForExternalIp(project: project.id, zone: zone.name, name: name);

      if (mounted) setState(() => _stage = 2); // installing
      final conn = ServerConnection(baseUrl: 'https://$ip:8080', apiKey: apiKey, provider: 'gcp');
      final fingerprint = await _pollHealth(conn);
      if (fingerprint == null) {
        throw ApiException('The VM booted but Lanway did not come up in time. It may '
            'still be installing — connect in a few minutes with key:\n$apiKey');
      }

      if (mounted) setState(() => _stage = 3); // connecting
      await ref.read(serverStoreProvider.notifier).add(
          conn.copyWith(certSha256: fingerprint.isEmpty ? null : fingerprint));
      if (mounted) setState(() => _step = _Step.done);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _step = _Step.choose;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Couldn’t reach Google while creating the server. If the Lanway VPN '
              'is connected, disconnect it and tap Create again.\n($e)';
          _step = _Step.choose;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Polls until the server answers, then returns its TLS cert fingerprint (for
  /// pinning) — or null if it never came up.
  Future<String?> _pollHealth(ServerConnection conn) async {
    final api = LanwayApiClient(conn);
    // e2-micro is slow to install (apt + Docker pull), so allow ~18 minutes.
    for (var i = 0; i < 216; i++) {
      try {
        if ((await api.health()).isOk) return api.observedCertSha256 ?? '';
      } catch (_) {/* not up yet */}
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create on Google Cloud'), backgroundColor: LanwayColors.navy),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: switch (_step) {
              _Step.connecting => _connecting(),
              _Step.choose => _choose(),
              _Step.provisioning => _provisioning(),
              _Step.done => _doneStep(),
            },
          ),
        ),
      ),
    );
  }

  Widget _connecting() {
    if (_error != null) return _errorBox(onRetry: () => _startOAuth());
    final title = _status.isNotEmpty
        ? _status
        : (_viaBrowser ? 'Waiting for Google…' : 'Loading your account…');
    return Column(
      children: [
        const SizedBox(height: 20),
        const SizedBox(
            width: 56, height: 56,
            child: CircularProgressIndicator(strokeWidth: 3, color: LanwayColors.accent)),
        const SizedBox(height: 28),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
        if (_viaBrowser && _status.isEmpty) ...[
          const SizedBox(height: 8),
          Text('A browser window opened for you to sign in and authorize Lanway. '
              'Come back here once you approve.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6), height: 1.5)),
          const SizedBox(height: 24),
          TextButton(onPressed: () => _startOAuth(), child: const Text('Reopen the browser')),
        ],
      ],
    );
  }

  Widget _choose() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose where to deploy',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white)),
        const SizedBox(height: 8),
        Text('A small e2-micro VM will be created. The US regions below are free-tier '
            'eligible on new accounts.',
            style: TextStyle(color: LanwayColors.mint, height: 1.4)),
        if (_email != null) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.account_circle, size: 18, color: LanwayColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Signed in as $_email',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.8), fontSize: 13)),
              ),
              TextButton(
                onPressed: _busy ? null : _switchAccount,
                child: const Text('Switch account'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const Text('Project', style: _labelStyle),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: LanwayColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18, color: LanwayColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _project == null ? 'LanwayServer' : '${_project!.name}  ·  ${_project!.id}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_busy)
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(_status.isEmpty ? 'Loading…' : _status,
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.7))),
            ],
          )
        else if (_needsBilling)
          _BillingBox(
            projectId: _project?.id,
            email: _email,
            onRetry: _prepareProject,
            onSwitch: _busy ? null : _switchAccount,
          )
        else if (_zonesError != null)
          _ApiDisabledBox(
            message: _zonesError!,
            projectId: _project?.id,
            busy: _busy,
            onRetry: _prepareProject,
          )
        else ...[
          const Text('Zone', style: _labelStyle),
          const SizedBox(height: 8),
          DropdownButtonFormField<GcpZone>(
            initialValue: _zone,
            isExpanded: true,
            dropdownColor: LanwayColors.surface,
            items: [
              for (final z in _zones)
                DropdownMenuItem(value: z, child: _zoneRow(z)),
            ],
            onChanged: (z) => setState(() => _zone = z),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (_busy || _needsBilling || _zone == null) ? null : _provision,
            icon: const Icon(Icons.bolt, size: 20),
            label: const Text('Create server'),
          ),
        ),
      ],
    );
  }

  static const _stageLabels = ['Creating your server', 'Booting up', 'Installing Lanway', 'Connecting'];

  Widget _provisioning() {
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
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(current,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('This usually takes 10–15 minutes. Keep this window open.',
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

  /// One row in the setup checklist: a tick when done, a spinner for the step in
  /// progress, and a dimmed circle for steps still ahead (DigitalOcean-style).
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

  Widget _errorBox({required VoidCallback onRetry}) {
    return Column(
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.error_outline, color: LanwayColors.danger, size: 48),
        const SizedBox(height: 16),
        Text(_error!,
            textAlign: TextAlign.center, style: const TextStyle(color: LanwayColors.mint, height: 1.5)),
        const SizedBox(height: 24),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

const _labelStyle = TextStyle(color: LanwayColors.mint, fontSize: 13, fontWeight: FontWeight.w500);

/// Maps a Compute Engine region to an ISO-3166 alpha-2 country code for its
/// flag (`assets/flags/{iso}.png`). All US regions share the US flag.
const _regionFlag = {
  'northamerica-northeast1': 'ca',
  'northamerica-northeast2': 'ca',
  'northamerica-south1': 'mx',
  'southamerica-east1': 'br',
  'southamerica-west1': 'cl',
  'europe-west1': 'be',
  'europe-west2': 'gb',
  'europe-west3': 'de',
  'europe-west4': 'nl',
  'europe-west6': 'ch',
  'europe-west8': 'it',
  'europe-west9': 'fr',
  'europe-west10': 'de',
  'europe-west12': 'it',
  'europe-central2': 'pl',
  'europe-north1': 'fi',
  'europe-north2': 'se',
  'europe-southwest1': 'es',
  'asia-east1': 'tw',
  'asia-east2': 'hk',
  'asia-northeast1': 'jp',
  'asia-northeast2': 'jp',
  'asia-northeast3': 'kr',
  'asia-south1': 'in',
  'asia-south2': 'in',
  'asia-southeast1': 'sg',
  'asia-southeast2': 'id',
  'australia-southeast1': 'au',
  'australia-southeast2': 'au',
  'me-west1': 'il',
  'me-central1': 'qa',
  'me-central2': 'sa',
  'africa-south1': 'za',
};

String? _flagIso(String region) => region.startsWith('us-') ? 'us' : _regionFlag[region];

/// Shown when the project has no billing account. We enable the API and link an
/// existing account automatically, but adding a *new* billing account needs a
/// payment method, which only the operator can do in the console (same as
/// Outline's "add a billing account" step).
class _BillingBox extends StatelessWidget {
  final String? projectId;
  final String? email;
  final VoidCallback onRetry;
  final VoidCallback? onSwitch;
  const _BillingBox({
    required this.projectId,
    required this.email,
    required this.onRetry,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LanwayColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LanwayColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No billing account is available for ${email ?? 'this account'}. Even the free '
            'e2-micro tier needs one. Either add a billing account to this account, or '
            'switch to the Google account that already has your billing — then tap Done.',
            style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.85), height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(projectId != null
                      ? 'https://console.cloud.google.com/billing/linkedaccount?project=$projectId'
                      : 'https://console.cloud.google.com/billing'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Add billing account'),
              ),
              if (onSwitch != null)
                OutlinedButton.icon(
                  onPressed: onSwitch,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LanwayColors.mint,
                    side: BorderSide(color: LanwayColors.mint.withValues(alpha: 0.4)),
                  ),
                  icon: const Icon(Icons.switch_account, size: 18),
                  label: const Text('Switch account'),
                ),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: LanwayColors.accent,
                  side: BorderSide(color: LanwayColors.accent.withValues(alpha: 0.5)),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when the selected project hasn't enabled a required API (usually
/// Compute Engine). Offers a one-click "Enable" link + retry, so the operator
/// doesn't have to leave and restart the whole flow.
class _ApiDisabledBox extends StatelessWidget {
  final String message;
  final String? projectId;
  final bool busy;
  final VoidCallback onRetry;
  const _ApiDisabledBox({
    required this.message,
    required this.projectId,
    required this.busy,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LanwayColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LanwayColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.85), height: 1.45, fontSize: 13)),
          const SizedBox(height: 14),
          Row(
            children: [
              if (projectId != null)
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                        'https://console.cloud.google.com/apis/library/compute.googleapis.com?project=$projectId'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Enable Compute Engine API'),
                ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: busy ? null : onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: LanwayColors.accent,
                  side: BorderSide(color: LanwayColors.accent.withValues(alpha: 0.5)),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
