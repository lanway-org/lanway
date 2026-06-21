import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vless/flutter_vless.dart';

import 'desktop_vpn.dart';
import 'models.dart';
import 'vless.dart';

/// iOS/macOS Network Extension identity. The plugin appends the Packet Tunnel
/// suffix (`.XrayTunnel`) to [_appBundleId] internally; the App Group must match
/// the one configured on both the Runner and XrayTunnel targets in Xcode.
const _appBundleId = 'org.lanway.lanwayClient';
const _appGroup = 'group.org.lanway.lanwayClient';

enum VpnStage { disconnected, connecting, connected, error }

/// Immutable snapshot of the tunnel state for the UI.
@immutable
class VpnState {
  final VpnStage stage;
  final SavedServer? server;
  final String duration;
  final int uploadSpeed;
  final int downloadSpeed;
  final String? error;

  const VpnState({
    this.stage = VpnStage.disconnected,
    this.server,
    this.duration = '00:00:00',
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.error,
  });

  bool get isConnected => stage == VpnStage.connected;
  bool get isBusy => stage == VpnStage.connecting;

  VpnState copyWith({
    VpnStage? stage,
    SavedServer? server,
    String? duration,
    int? uploadSpeed,
    int? downloadSpeed,
    String? error,
    bool clearError = false,
  }) {
    return VpnState(
      stage: stage ?? this.stage,
      server: server ?? this.server,
      duration: duration ?? this.duration,
      uploadSpeed: uploadSpeed ?? this.uploadSpeed,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives and observes the VPN tunnel. On Android/iOS it uses flutter_v2ray's
/// system VPN; on macOS it bundles Xray + the system proxy (DesktopVpn).
class VpnController extends StateNotifier<VpnState> {
  VpnController() : super(const VpnState()) {
    _mobile = Platform.isAndroid || Platform.isIOS;
    _desktop = Platform.isMacOS || Platform.isWindows;
    if (_mobile) {
      _vless = FlutterVless(onStatusChanged: _onStatus);
      _init();
    } else if (_desktop) {
      _desktopVpn = DesktopVpn();
    }
  }

  FlutterVless? _vless;
  DesktopVpn? _desktopVpn;
  bool _initialized = false;
  late final bool _mobile;
  late final bool _desktop;
  Timer? _ticker;
  DateTime? _connectedAt;

  bool get _supported => _mobile || _desktop;

  static const _unsupportedMsg =
      'VPN tunnelling isn’t available on this platform yet. Use the Lanway app '
      'on Android, iOS or macOS — adding and managing servers works everywhere.';

  Future<void> _init() async {
    try {
      await _vless!.initializeVless(
        providerBundleIdentifier: _appBundleId,
        groupIdentifier: _appGroup,
        // Android renders notification icons as a flat silhouette — use the
        // white road glyph, not the full-colour launcher icon.
        notificationIconResourceType: 'drawable',
        notificationIconResourceName: 'ic_stat_lanway',
      );
      _initialized = true;
    } catch (_) {
      // Plugin missing on this platform — handled by the platform guards.
    }
  }

  /// On desktop there's no status stream, so tick the elapsed time ourselves.
  void _startTicker() {
    _connectedAt = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final secs = DateTime.now().difference(_connectedAt!).inSeconds;
      final h = (secs ~/ 3600).toString().padLeft(2, '0');
      final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
      final s = (secs % 60).toString().padLeft(2, '0');
      state = state.copyWith(duration: '$h:$m:$s');
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onStatus(VlessStatus status) {
    final stage = switch (status.connectionState) {
      VlessConnectionState.connected => VpnStage.connected,
      VlessConnectionState.connecting => VpnStage.connecting,
      _ => VpnStage.disconnected,
    };
    state = state.copyWith(
      stage: stage,
      duration: _fmtDuration(status.duration),
      uploadSpeed: status.uploadSpeed,
      downloadSpeed: status.downloadSpeed,
    );
  }

  /// flutter_vless reports duration as whole seconds; the UI shows HH:MM:SS.
  String _fmtDuration(int secs) {
    final h = (secs ~/ 3600).toString().padLeft(2, '0');
    final m = ((secs % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Connects to [server]. [dns] optionally pins DNS resolvers for the tunnel.
  Future<void> connect(SavedServer server, {List<String> dns = const []}) async {
    if (!_supported) {
      state = state.copyWith(stage: VpnStage.error, server: server, error: _unsupportedMsg);
      return;
    }
    state = state.copyWith(stage: VpnStage.connecting, server: server, clearError: true);

    final parsed = parseShareLink(server.link);
    if (parsed == null) {
      state = state.copyWith(stage: VpnStage.error, error: 'This server link is not valid.');
      return;
    }

    try {
      if (_desktop) {
        await _desktopVpn!.connect(parsed.vless, dns: dns);
        _startTicker();
        state = state.copyWith(stage: VpnStage.connected);
        return;
      }

      // Mobile (Android/iOS) — full system VPN.
      if (!_initialized) await _init();
      final granted = await _vless!.requestPermission();
      if (!granted) {
        state = state.copyWith(stage: VpnStage.error, error: 'VPN permission was denied.');
        return;
      }
      await _vless!.startVless(
        remark: server.name,
        config: buildClientConfig(parsed.vless, dns: dns),
        proxyOnly: false,
      );
    } catch (e) {
      state = state.copyWith(stage: VpnStage.error, error: _friendly(e));
    }
  }

  Future<void> disconnect() async {
    _stopTicker();
    try {
      if (_desktop) {
        await _desktopVpn!.disconnect();
      } else if (_mobile && _vless != null) {
        await _vless!.stopVless();
      }
    } catch (_) {/* best effort */}
    state = state.copyWith(stage: VpnStage.disconnected, duration: '00:00:00', uploadSpeed: 0, downloadSpeed: 0);
  }

  /// Measures round-trip delay (ms) to [server]; returns -1 on failure. On
  /// mobile we ask the core; on desktop we time a TCP handshake to the host.
  Future<int> ping(SavedServer server) async {
    final parsed = parseShareLink(server.link);
    if (parsed == null) return -1;
    if (_mobile && _vless != null) {
      try {
        final url = toVlessURL(parsed.vless);
        return await _vless!.getServerDelay(config: url.getFullConfiguration());
      } catch (_) {
        return -1;
      }
    }
    return _tcpPing(parsed.vless);
  }

  /// Times a raw TCP connect to the server's host:port — works whether or not
  /// the tunnel is up, since the REALITY port listens like any HTTPS server.
  Future<int> _tcpPing(String vless) async {
    final m = RegExp(r'@([^:/?#]+):(\d+)').firstMatch(vless);
    if (m == null) return -1;
    final host = m.group(1)!;
    final port = int.tryParse(m.group(2)!) ?? 443;
    try {
      final sw = Stopwatch()..start();
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      sw.stop();
      socket.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  String _friendly(Object e) {
    if (e is FormatException) return e.message;
    return 'Could not start the tunnel. $e';
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}

final vpnControllerProvider =
    StateNotifierProvider<VpnController, VpnState>((ref) => VpnController());
