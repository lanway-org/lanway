import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dns_settings.dart';
import '../storage.dart';
import '../theme.dart';
import '../vpn_controller.dart';
import '../widgets/brand.dart';
import '../widgets/world_map.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeServerProvider);
    final stage = ref.watch(vpnControllerProvider.select((s) => s.stage));
    final glow = _stageColor(stage);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(gradient: _bgGradient(stage)),
        child: Stack(
          children: [
            // Soft glow that pools behind the connect button, tinted by state.
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.9,
                    colors: [glow.withValues(alpha: 0.18), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Dotted world map, a touch brighter once connected.
            Positioned.fill(
              child: DottedWorld(
                color: stage == VpnStage.connected ? glow : Colors.white,
                opacity: stage == VpnStage.connected ? 0.13 : 0.07,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _Header(),
                  Expanded(child: active == null ? _NoServer() : _ConnectBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page backdrop shifts colour with the tunnel state.
LinearGradient _bgGradient(VpnStage s) {
  final List<Color> colors = switch (s) {
    VpnStage.connected => const [Color(0xFF06283D), Color(0xFF06141F)],
    VpnStage.connecting => const [Color(0xFF2A2410), Color(0xFF0A1628)],
    VpnStage.error => const [Color(0xFF2A1414), Color(0xFF0A1628)],
    VpnStage.disconnected => const [Color(0xFF101D32), Color(0xFF070F1C)],
  };
  return LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors);
}

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          const LanwayLogo(size: 30),
          const SizedBox(width: 10),
          const LanwayWordmark(fontSize: 18),
          const Spacer(),
          IconButton(
            tooltip: 'Servers',
            onPressed: () => context.push('/servers'),
            icon: const Icon(Icons.dns_outlined, color: LanwayColors.mint),
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

class _ConnectBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnControllerProvider);
    final active = ref.watch(activeServerProvider)!;
    final controller = ref.read(vpnControllerProvider.notifier);

    return Column(
      children: [
        const Spacer(),
        _ConnectButton(
          stage: vpn.stage,
          onTap: () {
            if (vpn.isConnected || vpn.stage == VpnStage.connecting) {
              controller.disconnect();
            } else {
              controller.connect(active, dns: ref.read(dnsServersProvider));
            }
          },
        ),
        const SizedBox(height: 28),
        Text(
          _statusLabel(vpn.stage),
          style: TextStyle(
            color: _stageColor(vpn.stage),
            fontWeight: FontWeight.w500,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => context.push('/servers'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(active.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15)),
              const SizedBox(width: 4),
              Icon(Icons.unfold_more, size: 16, color: LanwayColors.mint.withValues(alpha: 0.5)),
            ],
          ),
        ),
        if (vpn.error != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(vpn.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: LanwayColors.danger, fontSize: 13)),
          ),
        ],
        const Spacer(),
        if (vpn.isConnected) ...[
          Text('Connected for ${vpn.duration}',
              style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(
            width: 240,
            child: FilledButton.icon(
              onPressed: () => context.push('/speedtest'),
              icon: const Icon(Icons.speed, size: 20),
              label: const Text('Test speed'),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  String _statusLabel(VpnStage s) => switch (s) {
        VpnStage.connected => 'Connected',
        VpnStage.connecting => 'Connecting…',
        VpnStage.error => 'Not connected',
        VpnStage.disconnected => 'Tap to connect',
      };
}

Color _stageColor(VpnStage s) => switch (s) {
      VpnStage.connected => LanwayColors.accent,
      VpnStage.connecting => LanwayColors.amber,
      _ => LanwayColors.mint.withValues(alpha: 0.6),
    };

class _ConnectButton extends StatefulWidget {
  final VpnStage stage;
  final VoidCallback onTap;
  const _ConnectButton({required this.stage, required this.onTap});

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> with SingleTickerProviderStateMixin {
  // Created eagerly in initState (not lazily) so dispose() never has to spin up a
  // Ticker against a deactivated widget — which crashes if we were never connected.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _stageColor(widget.stage);
    final connected = widget.stage == VpnStage.connected;
    final connecting = widget.stage == VpnStage.connecting;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 240,
        height: 240,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Expanding pulse — lively while connecting, gentle once connected.
            if (connected || connecting)
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, _) {
                  final v = _pulse.value;
                  return Container(
                    width: 180 + v * (connecting ? 70 : 40),
                    height: 180 + v * (connecting ? 70 : 40),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: (1 - v) * (connecting ? 0.30 : 0.15)),
                    ),
                  );
                },
              ),
            // A spinner ring while connecting, to show it's working.
            if (connecting)
              const SizedBox(
                width: 196,
                height: 196,
                child: CircularProgressIndicator(strokeWidth: 3, color: LanwayColors.amber),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: connected
                    ? const LinearGradient(
                        colors: [LanwayColors.accent, LanwayColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: connected ? null : LanwayColors.surface,
                border: Border.all(
                  color: connected ? Colors.transparent : color.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.power_settings_new,
                  size: 96,
                  color: connected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoServer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key_off_outlined, size: 56, color: LanwayColors.mint.withValues(alpha: 0.4)),
            const SizedBox(height: 20),
            const Text('No server yet',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Add a server by scanning a QR code or pasting a key your server admin shared.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6))),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/add'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add a server'),
            ),
          ],
        ),
      ),
    );
  }
}
