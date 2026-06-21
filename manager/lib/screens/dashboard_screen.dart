import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/brand.dart';

/// A light, thin-stroke house — much softer than the filled Material glyph.
const _homeIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="#E6EEF7" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M3 10.6 12 3.5l9 7.1"/><path d="M5.3 9.4V20h13.4V9.4"/></svg>';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    // Live-update stats + users while the dashboard is open (the server's own
    // 60s poller keeps the numbers fresh; this just re-reads them).
    _autoRefresh = Timer.periodic(const Duration(seconds: 10), (_) => _invalidate());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(statsProvider);
    ref.invalidate(usersProvider);
  }

  /// Manual refresh: force an immediate server-side traffic poll so usage shows
  /// right away (instead of waiting up to 60s), then re-read. Surfaces a clear
  /// message if the server can't read traffic stats at all.
  Future<void> _refreshNow() async {
    final api = ref.read(apiClientProvider);
    try {
      final r = await api?.pollUsage();
      if (r?.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Traffic stats unavailable: ${r!.error}'),
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (_) {
      // Older servers without the poll endpoint — fall back to a plain re-read.
    }
    _invalidate();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final users = ref.watch(usersProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onRefresh: _refreshNow),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshNow,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    stats.when(
                      data: (s) => _StatsRow(stats: s),
                      loading: () => const _StatsLoading(),
                      error: (e, _) => _ErrorBanner(message: '$e'),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Text('Users',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () => _showAddUser(context, ref),
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Add user'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    users.when(
                      data: (list) => list.isEmpty
                          ? const _EmptyUsers()
                          : Column(
                              children: [
                                for (final u in list) _UserTile(user: u, onChanged: _invalidate),
                              ],
                            ),
                      loading: () => Column(
                        children: const [
                          _UserSkeleton(),
                          _UserSkeleton(),
                          _UserSkeleton(),
                        ],
                      ),
                      error: (e, _) => _ErrorBanner(message: '$e'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddUser(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (created == true) _invalidate();
  }
}

class _TopBar extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _TopBar({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Home — your servers',
            onPressed: () => context.go('/connect'),
            icon: SvgPicture.string(_homeIconSvg, width: 26, height: 26),
          ),
          const SizedBox(width: 8),
          const LanwayLogo(size: 32),
          const SizedBox(width: 10),
          const LanwayWordmark(fontSize: 18),
          const SizedBox(width: 14),
          if (conn != null)
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(conn.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                  Text('${conn.platformLabel}  ·  ${conn.host}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, color: LanwayColors.mint),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined, color: LanwayColors.mint),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final ServerStats stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _StatCard(label: 'Total users', value: '${stats.totalUsers}', icon: Icons.people_outline),
        _StatCard(
            label: 'Bandwidth used',
            value: formatBytes(stats.bandwidthBytes),
            icon: Icons.swap_vert),
        _StatCard(
            label: 'Uptime', value: formatUptime(stats.uptimeSeconds), icon: Icons.timer_outlined),
        _StatCard(
            label: 'Stealth mode',
            value: stats.mode == 'reality' ? 'REALITY' : 'TLS',
            icon: Icons.shield_outlined,
            tooltip: stats.mode == 'reality'
                ? 'REALITY — your tunnel borrows a real website’s TLS handshake, so '
                    'to a censor the traffic looks like ordinary HTTPS to that site. '
                    'Hardest to detect or block; no domain needed.'
                : 'TLS — the tunnel is wrapped in standard HTTPS on your own domain.'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? tooltip;
  const _StatCard({required this.label, required this.value, required this.icon, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: LanwayColors.accent, size: 22),
              if (tooltip != null) ...[
                const Spacer(),
                _InfoButton(title: label, message: tooltip!),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 13)),
        ],
      ),
    );
    return card;
  }
}

/// A small "?" that opens a short explanation dialog (used for the stealth mode
/// card — the text is too long for a hover tooltip).
class _InfoButton extends StatelessWidget {
  final String title;
  final String message;
  const _InfoButton({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: LanwayColors.surface,
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Text(message, style: const TextStyle(height: 1.5)),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
            ],
          ),
        ),
        child: Icon(Icons.help_outline, size: 16, color: LanwayColors.mint.withValues(alpha: 0.5)),
      ),
    );
  }
}

class _StatsLoading extends StatelessWidget {
  const _StatsLoading();
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: const [
        _SkeletonBox(width: 200, height: 116),
        _SkeletonBox(width: 200, height: 116),
        _SkeletonBox(width: 200, height: 116),
        _SkeletonBox(width: 200, height: 116),
      ],
    );
  }
}

/// A single placeholder user row shown while the list loads.
class _UserSkeleton extends StatelessWidget {
  const _UserSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Row(
        children: const [
          _SkeletonBox(width: 36, height: 36, radius: 18),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                _SkeletonBox(width: 90, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A pulsing grey placeholder block used to build skeleton screens.
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const _SkeletonBox({required this.width, required this.height, this.radius = 8});
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(const Color(0x11FFFFFF), const Color(0x22FFFFFF), _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final VpnUser user;
  final VoidCallback onChanged;
  const _UserTile({required this.user, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitLabel = user.unlimited
        ? '${formatBytes(user.usedBytes)} used · unlimited'
        : '${formatBytes(user.usedBytes)} of ${user.dataLimitGB.toStringAsFixed(0)} GB';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: LanwayColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: LanwayColors.accent.withValues(alpha: 0.15),
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: LanwayColors.accent, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
                        ),
                        if (!user.enabled) ...[
                          const SizedBox(width: 8),
                          const _Pill(label: 'over limit', color: LanwayColors.danger),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(limitLabel,
                        style: TextStyle(
                            color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Share key',
                onPressed: () => context.push('/share/${user.id}'),
                icon: const Icon(Icons.qr_code_2, color: LanwayColors.accent),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline, color: Colors.white),
              ),
            ],
          ),
          if (!user.unlimited) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: user.usageFraction,
                minHeight: 6,
                backgroundColor: const Color(0x1AFFFFFF),
                color: user.usageFraction > 0.9 ? LanwayColors.danger : LanwayColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LanwayColors.surface,
        title: const Text('Delete user?'),
        content: Text('“${user.name}” will lose access immediately. This cannot be undone.'),
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
    if (yes != true) return;
    final api = ref.read(apiClientProvider);
    try {
      await api?.deleteUser(user.id);
      onChanged();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog();
  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _nameCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  bool _unlimited = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    double limit = 0;
    if (!_unlimited) {
      limit = double.tryParse(_limitCtrl.text.trim()) ?? -1;
      if (limit <= 0) {
        setState(() => _error = 'Enter a data limit in GB, or choose unlimited.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(apiClientProvider);
    try {
      await api!.createUser(name: name, dataLimitGB: limit);
      if (mounted) Navigator.pop(context, true);
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
      title: const Text('Add user', style: TextStyle(fontWeight: FontWeight.w500)),
      content: SizedBox(
        width: 420,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Mom’s phone'),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _unlimited,
            onChanged: (v) => setState(() => _unlimited = v),
            title: const Text('Unlimited data',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400)),
            activeThumbColor: LanwayColors.accent,
          ),
          if (!_unlimited)
            TextField(
              controller: _limitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Data limit (GB)', hintText: '50'),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
          ],
        ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.person_add_alt, color: LanwayColors.mint.withValues(alpha: 0.4), size: 40),
          const SizedBox(height: 12),
          Text('No users yet. Add one to generate a key.',
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LanwayColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LanwayColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: LanwayColors.danger),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: LanwayColors.mint))),
        ],
      ),
    );
  }
}
