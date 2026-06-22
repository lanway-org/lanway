import 'dart:convert';
import 'dart:io';

/// The exit IP and where it geolocates to.
class IpInfo {
  final String ip;
  final String city;
  final String country;
  final String isp;
  final double lat;
  final double lon;
  const IpInfo({
    required this.ip,
    required this.city,
    required this.country,
    required this.isp,
    required this.lat,
    required this.lon,
  });

  static const empty = IpInfo(ip: '—', city: '', country: '', isp: '', lat: 0, lon: 0);

  String get place => [city, country].where((s) => s.isNotEmpty).join(', ');
}

/// Which stage of the test is running.
enum SpeedPhase { ping, download, upload, done }

/// A live snapshot emitted while the test runs. The gauge reads [mbps] +
/// [fraction] for the active [phase]; the results card reads the finals.
class SpeedProgress {
  final SpeedPhase phase;
  final double mbps; // instantaneous reading for the active phase
  final double fraction; // 0..1 progress of the active phase
  final IpInfo ip;
  final int latencyMs;
  final double downloadMbps;
  final double uploadMbps;

  const SpeedProgress({
    required this.phase,
    this.mbps = 0,
    this.fraction = 0,
    this.ip = IpInfo.empty,
    this.latencyMs = 0,
    this.downloadMbps = 0,
    this.uploadMbps = 0,
  });
}

/// Measures the connection's exit IP, location, download and upload speed,
/// emitting live progress so the UI can animate a speedometer. Every platform
/// now tunnels the whole device (a TUN interface on desktop, the VPN service on
/// mobile), so plain requests already reflect the VPN's exit.
class SpeedTester {
  static HttpClient _client() => HttpClient()..connectionTimeout = const Duration(seconds: 15);

  static Future<IpInfo> _lookupIp(HttpClient c) async {
    // Must be HTTPS — iOS App Transport Security blocks plain-HTTP requests
    // (the old http://ip-api.com call silently failed the whole test on iPhone).
    final req = await c.getUrl(Uri.parse('https://ipwho.is/'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final conn = j['connection'] as Map<String, dynamic>?;
    return IpInfo(
      ip: (j['ip'] as String?) ?? '—',
      city: (j['city'] as String?) ?? '',
      country: (j['country'] as String?) ?? '',
      isp: (conn?['isp'] as String?) ?? (conn?['org'] as String?) ?? '',
      lat: (j['latitude'] as num?)?.toDouble() ?? 0,
      lon: (j['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  /// A short ping: the lowest round-trip of a few tiny requests (the first one
  /// pays the TLS handshake, later ones reuse the connection — min ≈ true RTT).
  static Future<int> _measureLatency(HttpClient c) async {
    var best = 1 << 30;
    for (var i = 0; i < 4; i++) {
      try {
        final t = DateTime.now();
        final req = await c.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=0'));
        final resp = await req.close();
        await resp.drain<void>();
        final ms = DateTime.now().difference(t).inMilliseconds;
        if (ms < best) best = ms;
      } catch (_) {/* ignore a flaky probe */}
    }
    return best == (1 << 30) ? 0 : best;
  }

  /// Runs the full test, yielding progress as it goes. The final event has
  /// [phase] == [SpeedPhase.done] with the measured download/upload/latency.
  static Stream<SpeedProgress> run() async* {
    final c = _client();
    var ip = IpInfo.empty;
    var latency = 0;
    var dl = 0.0;
    try {
      // 1) Exit IP (so we can show location/ISP straight away) + a real ping.
      yield SpeedProgress(phase: SpeedPhase.ping, ip: ip);
      ip = await _lookupIp(c);
      yield SpeedProgress(phase: SpeedPhase.ping, ip: ip);
      latency = await _measureLatency(c);
      yield SpeedProgress(phase: SpeedPhase.ping, ip: ip, latencyMs: latency, fraction: 1);

      // 2) Download — pull ~25 MB; the live number is a trailing-window rate so
      // it reflects current throughput (not a since-start average).
      const totalDl = 25000000;
      final req = await c.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=$totalDl'));
      final resp = await req.close();
      final dStart = DateTime.now();
      final dWin = <List<int>>[];
      var got = 0;
      var lastEmit = dStart;
      await for (final chunk in resp) {
        got += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastEmit).inMilliseconds >= 80) {
          lastEmit = now;
          yield SpeedProgress(
              phase: SpeedPhase.download,
              mbps: _windowRate(dWin, now.difference(dStart).inMilliseconds, got),
              fraction: got / totalDl,
              ip: ip,
              latencyMs: latency);
        }
      }
      final dSecs = DateTime.now().difference(dStart).inMilliseconds / 1000.0;
      dl = dSecs <= 0 ? 0 : (got * 8 / 1e6) / dSecs; // final = average
      yield SpeedProgress(
          phase: SpeedPhase.download,
          mbps: dl,
          fraction: 1,
          downloadMbps: dl,
          ip: ip,
          latencyMs: latency);

      // 3) Upload — push ~15 MB. The OS send buffer absorbs the first burst, so
      // a since-start average over-reads badly; use the same trailing window,
      // which settles to the real wire speed once the buffer is saturated.
      const totalUl = 15000000;
      const chunkSize = 65536;
      final filler = List<int>.filled(chunkSize, 120);
      final upReq = await c.postUrl(Uri.parse('https://speed.cloudflare.com/__up'));
      upReq.headers.contentType = ContentType('application', 'octet-stream');
      upReq.contentLength = totalUl;
      final uStart = DateTime.now();
      final uWin = <List<int>>[];
      var sent = 0;
      var lastU = uStart;
      while (sent < totalUl) {
        final n = (totalUl - sent) < chunkSize ? (totalUl - sent) : chunkSize;
        upReq.add(n == chunkSize ? filler : filler.sublist(0, n));
        await upReq.flush(); // backpressures once the socket buffer fills
        sent += n;
        final now = DateTime.now();
        if (now.difference(lastU).inMilliseconds >= 80) {
          lastU = now;
          yield SpeedProgress(
              phase: SpeedPhase.upload,
              mbps: _windowRate(uWin, now.difference(uStart).inMilliseconds, sent),
              fraction: sent / totalUl,
              downloadMbps: dl,
              ip: ip,
              latencyMs: latency);
        }
      }
      final upResp = await upReq.close();
      await upResp.drain<void>();
      final uSecs = DateTime.now().difference(uStart).inMilliseconds / 1000.0;
      final ul = uSecs <= 0 ? 0.0 : (totalUl * 8 / 1e6) / uSecs; // final = average

      yield SpeedProgress(
          phase: SpeedPhase.done,
          mbps: ul,
          fraction: 1,
          downloadMbps: dl,
          uploadMbps: ul,
          ip: ip,
          latencyMs: latency);
    } finally {
      c.close(force: true);
    }
  }

  /// Throughput (Mbps) over a trailing ~800 ms window. [win] holds [ms, bytes]
  /// samples; old ones are dropped so the rate tracks the current speed.
  static double _windowRate(List<List<int>> win, int ms, int bytes) {
    win.add([ms, bytes]);
    const windowMs = 800;
    while (win.length > 2 && ms - win.first[0] > windowMs) {
      win.removeAt(0);
    }
    final dt = ms - win.first[0];
    final db = bytes - win.first[1];
    if (dt <= 0) return 0;
    return (db * 8 / 1e6) / (dt / 1000.0);
  }
}
