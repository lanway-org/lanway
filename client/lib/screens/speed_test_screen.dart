import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../speed_test.dart';
import '../theme.dart';
import '../widgets/world_map.dart';

/// Runs a connection test with a live speedtest.net-style graph — a big rolling
/// number over an animated area chart — then shows the exit IP on a map with
/// download, upload and latency.
class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});
  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  StreamSubscription<SpeedProgress>? _sub;
  SpeedProgress? _latest;
  Object? _error;
  final List<double> _samples = [];
  SpeedPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _run() {
    _sub?.cancel();
    setState(() {
      _latest = null;
      _error = null;
      _samples.clear();
      _lastPhase = null;
    });
    _sub = SpeedTester.run().listen(
      (p) {
        setState(() {
          // Restart the graph when the phase flips (download → upload).
          if (p.phase != _lastPhase) {
            _samples.clear();
            _lastPhase = p.phase;
          }
          if (p.phase == SpeedPhase.download || p.phase == SpeedPhase.upload) {
            _samples.add(p.mbps);
          }
          _latest = p;
        });
      },
      onError: (Object e) => setState(() => _error = e),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = () {
      if (_error != null) return _Failed(onRetry: _run);
      final p = _latest;
      if (p != null && p.phase == SpeedPhase.done) {
        return _Results(result: p, onRetry: _run);
      }
      return _Live(progress: p ?? const SpeedProgress(phase: SpeedPhase.ping), samples: _samples);
    }();

    // Tint the backdrop by the active phase (blue for download, amber for upload).
    final glow = _latest?.phase == SpeedPhase.upload ? LanwayColors.amber : LanwayColors.accent;
    // Hide the world map once the results screen (with its own map) takes over.
    final showWorld = _latest == null || _latest!.phase != SpeedPhase.done;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection test'),
        backgroundColor: const Color(0xFF06283D),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF06283D), Color(0xFF06141F)],
          ),
        ),
        child: Stack(
          children: [
            if (showWorld) ...[
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.9,
                      colors: [glow.withValues(alpha: 0.16), Colors.transparent],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(child: DottedWorld(color: Colors.white, opacity: 0.07)),
            ],
            body,
          ],
        ),
      ),
    );
  }
}

String _fmt(double mbps) => mbps >= 100 ? mbps.toStringAsFixed(0) : mbps.toStringAsFixed(1);

/// The live testing view: summary row, big rolling number, and an area graph.
class _Live extends StatelessWidget {
  final SpeedProgress progress;
  final List<double> samples;
  const _Live({required this.progress, required this.samples});

  @override
  Widget build(BuildContext context) {
    final isUpload = progress.phase == SpeedPhase.upload;
    final color = isUpload ? LanwayColors.amber : LanwayColors.accent;
    final phaseLabel = switch (progress.phase) {
      SpeedPhase.ping => 'Finding your exit…',
      SpeedPhase.download => 'Download',
      SpeedPhase.upload => 'Upload',
      SpeedPhase.done => 'Done',
    };
    final value = progress.phase == SpeedPhase.ping ? 0.0 : progress.mbps;

    return Column(
      children: [
        const SizedBox(height: 20),
        // Top summary, like speedtest's ping · download · upload header.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.south_rounded,
                  label: 'Download',
                  value: progress.downloadMbps > 0
                      ? _fmt(progress.downloadMbps)
                      : (progress.phase == SpeedPhase.download ? _fmt(progress.mbps) : '—'),
                  active: progress.phase == SpeedPhase.download,
                  color: LanwayColors.accent,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.north_rounded,
                  label: 'Upload',
                  value: progress.phase == SpeedPhase.upload ? _fmt(progress.mbps) : '—',
                  active: progress.phase == SpeedPhase.upload,
                  color: LanwayColors.amber,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  icon: Icons.timer_outlined,
                  label: 'Ping',
                  value: progress.latencyMs > 0 ? '${progress.latencyMs} ms' : '—',
                  active: progress.phase == SpeedPhase.ping,
                  color: LanwayColors.mint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        // Big rolling readout.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isUpload ? Icons.north_rounded : Icons.south_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(phaseLabel,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              tween: Tween(end: value),
              builder: (_, v, _) => Text(_fmt(v),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 64, fontWeight: FontWeight.w600, height: 1)),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Mbps',
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.5), fontSize: 16)),
            ),
          ],
        ),
        if (progress.ip.isp.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.public, size: 14, color: LanwayColors.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  progress.ip.place.isEmpty
                      ? progress.ip.isp
                      : '${progress.ip.isp} · ${progress.ip.place}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6), fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        const Spacer(),
        // Live area graph that fills the lower part of the screen.
        SizedBox(
          height: 200,
          width: double.infinity,
          child: CustomPaint(painter: _ChartPainter(samples: samples, color: color)),
        ),
      ],
    );
  }
}

/// Smooth filled area chart of the speed samples over time.
class _ChartPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  _ChartPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    var maxV = 10.0;
    for (final s in samples) {
      if (s > maxV) maxV = s;
    }
    maxV *= 1.15; // headroom

    final n = samples.length;
    Offset pointAt(int i) {
      final x = i / (n - 1) * size.width;
      final y = size.height - (samples[i] / maxV).clamp(0.0, 1.0) * (size.height - 8) - 4;
      return Offset(x, y);
    }

    // Smooth line via midpoint quadratics.
    final line = Path()..moveTo(0, pointAt(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final p = pointAt(i);
      final q = pointAt(i + 1);
      final mid = Offset((p.dx + q.dx) / 2, (p.dy + q.dy) / 2);
      line.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
    }
    line.lineTo(size.width, pointAt(n - 1).dy);

    // Fill under the line.
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Leading dot.
    final last = pointAt(n - 1);
    canvas.drawCircle(last, 4, Paint()..color = color);
    canvas.drawCircle(last, 8, Paint()..color = color.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final Color color;
  const _MiniStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.active,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: active ? color : LanwayColors.mint.withValues(alpha: 0.4)),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                color: active ? Colors.white : LanwayColors.mint.withValues(alpha: 0.7),
                fontSize: 15,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.45), fontSize: 11)),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  final VoidCallback onRetry;
  const _Failed({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: LanwayColors.mint.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('Couldn’t run the test',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Connect first, then try again.',
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

class _Results extends StatelessWidget {
  final SpeedProgress result;
  final VoidCallback onRetry;
  const _Results({required this.result, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final ip = result.ip;
    final point = LatLng(ip.lat, ip.lon);
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            child: FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 5),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.lanway.client',
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: point,
                    width: 44,
                    height: 44,
                    child: const Icon(Icons.location_on, color: LanwayColors.accent, size: 44),
                  ),
                ]),
              ],
            ),
          ),
        ),
        Container(
          color: LanwayColors.navy,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.public, color: LanwayColors.accent, size: 20),
                  const SizedBox(width: 10),
                  Text(ip.place.isEmpty ? 'Unknown location' : ip.place,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Exit IP ${ip.ip}${ip.isp.isNotEmpty ? ' · ${ip.isp}' : ''}',
                  style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.6), fontSize: 13)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                        icon: Icons.south_rounded,
                        label: 'Download',
                        value: '${_fmt(result.downloadMbps)} Mbps'),
                  ),
                  Expanded(
                    child: _Metric(
                        icon: Icons.north_rounded,
                        label: 'Upload',
                        value: '${_fmt(result.uploadMbps)} Mbps'),
                  ),
                  Expanded(
                    child: _Metric(
                        icon: Icons.timer_outlined,
                        label: 'Latency',
                        value: '${result.latencyMs} ms'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: LanwayColors.accent,
                    side: BorderSide(color: LanwayColors.accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Test again'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Metric({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: LanwayColors.accent),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: LanwayColors.mint.withValues(alpha: 0.55), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
