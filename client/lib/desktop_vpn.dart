import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'vless.dart';

/// Runs the VPN tunnel on desktop (macOS) by launching a bundled Xray core as a
/// local SOCKS proxy and pointing the system proxy at it. This is the same
/// approach desktop VLESS clients (v2rayU, Clash) use — no kernel extension.
///
/// macOS sets the proxy via `networksetup`; Windows via the WinINET registry.
class DesktopVpn {
  Process? _proc;

  bool get isActive => _proc != null;

  /// The local SOCKS port the bundled core listens on (matches the config that
  /// flutter_v2ray's parser produces). We add an HTTP proxy on socksPort+1 so
  /// apps that only honour an HTTP proxy are covered too.
  static const int socksPort = 1080;
  static const int httpPort = 1081;

  /// Connects: extract the core, run it as a local SOCKS+HTTP proxy, then turn
  /// on the system proxy. Throws with a friendly message on failure.
  Future<void> connect(String vlessLink, {List<String> dns = const []}) async {
    final configJson = buildClientConfig(vlessLink, dns: dns, httpInbound: true);

    final dir = await getApplicationSupportDirectory();
    final configFile = File('${dir.path}/lanway-xray.json');
    await configFile.writeAsString(configJson);

    final xrayPath = await _ensureBinary(dir);

    final proc = await Process.start(xrayPath, ['run', '-config', configFile.path]);
    _proc = proc;

    final errBuf = StringBuffer();
    proc.stderr.transform(const SystemEncoding().decoder).listen(errBuf.write);
    proc.stdout.drain<void>();

    // If the core dies within the first moment, surface why (e.g. bad config).
    final early = await Future.any<int?>([
      proc.exitCode,
      Future<int?>.delayed(const Duration(milliseconds: 900), () => null),
    ]);
    if (early != null) {
      _proc = null;
      throw Exception('The VPN core stopped (code $early). ${errBuf.toString().trim()}');
    }

    await _setSystemProxy(on: true);
  }

  /// Turns off the system proxy and stops the core.
  Future<void> disconnect() async {
    try {
      await _setSystemProxy(on: false);
    } catch (_) {/* best effort */}
    _proc?.kill();
    _proc = null;
  }

  /// Copies the bundled core to app support (once), marks it executable, and
  /// returns its path.
  Future<String> _ensureBinary(Directory dir) async {
    final assetPath = Platform.isWindows ? 'assets/bin/xray_windows.exe' : 'assets/bin/xray_macos';
    final out = File('${dir.path}/${Platform.isWindows ? 'lanway-core.exe' : 'lanway-core'}');

    if (!await out.exists() || (await out.length()) == 0) {
      final ByteData data;
      try {
        data = await rootBundle.load(assetPath);
      } catch (_) {
        throw Exception('The VPN core is not bundled in this build. '
            'Add the Xray binary to assets/bin/ and rebuild.');
      }
      await out.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', out.path]);
      }
    }
    return out.path;
  }

  /// Points the system proxy at the local core (or clears it). Per-platform:
  /// macOS uses `networksetup`, Windows the WinINET registry keys.
  Future<void> _setSystemProxy({required bool on}) async {
    if (Platform.isMacOS) return _setSystemProxyMacOS(on: on);
    if (Platform.isWindows) return _setSystemProxyWindows(on: on);
  }

  /// Sets the Windows per-user proxy via the WinINET registry keys. No elevation
  /// is needed (HKCU), so there's no password prompt. Routes HTTP/HTTPS through
  /// the local HTTP proxy; localhost is excluded so the app can still reach the
  /// core. Existing apps pick this up on their next connection.
  Future<void> _setSystemProxyWindows({required bool on}) async {
    const root = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    Future<void> reg(List<String> args) async {
      final res = await Process.run('reg', args);
      if (res.exitCode != 0) {
        throw Exception('Could not change the system proxy. ${res.stderr}');
      }
    }

    if (on) {
      await reg([
        'add', root, '/v', 'ProxyServer', '/t', 'REG_SZ',
        '/d', '127.0.0.1:$httpPort', '/f',
      ]);
      await reg([
        'add', root, '/v', 'ProxyOverride', '/t', 'REG_SZ',
        '/d', 'localhost;127.*;<local>', '/f',
      ]);
      await reg(['add', root, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    } else {
      await reg(['add', root, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
    }
  }

  /// Sets the macOS system SOCKS+HTTP proxy to the local core, for every active
  /// network service. Uses a one-time passwordless helper so the user is only
  /// prompted for their password once, ever (not on every connect/disconnect).
  Future<void> _setSystemProxyMacOS({required bool on}) async {
    await _ensureProxyHelper();

    const ns = 'sudo -n /usr/sbin/networksetup';
    final perService = on
        ? '$ns -setsocksfirewallproxy "\$svc" 127.0.0.1 $socksPort; '
            '$ns -setsocksfirewallproxystate "\$svc" on; '
            '$ns -setwebproxy "\$svc" 127.0.0.1 $httpPort; '
            '$ns -setsecurewebproxy "\$svc" 127.0.0.1 $httpPort; '
            '$ns -setwebproxystate "\$svc" on; '
            '$ns -setsecurewebproxystate "\$svc" on'
        : '$ns -setsocksfirewallproxystate "\$svc" off; '
            '$ns -setwebproxystate "\$svc" off; '
            '$ns -setsecurewebproxystate "\$svc" off';

    final script = '/usr/sbin/networksetup -listallnetworkservices | tail -n +2 | '
        'grep -v "^\\*" | while read svc; do $perService; done';

    final res = await Process.run('sh', ['-c', script]);
    if (res.exitCode != 0) {
      throw Exception('Could not change the system proxy. ${res.stderr}');
    }
  }

  /// Installs a narrow sudoers rule (once) so `networksetup` can run without a
  /// password thereafter. Prompts for admin only the first time.
  Future<void> _ensureProxyHelper() async {
    // Already installed? `sudo -n` succeeds without a password if so.
    final check = await Process.run(
        'sudo', ['-n', '/usr/sbin/networksetup', '-listallnetworkservices']);
    if (check.exitCode == 0) return;

    final user = Platform.environment['USER'] ??
        (await Process.run('whoami', [])).stdout.toString().trim();
    final rule = '$user ALL=(root) NOPASSWD: /usr/sbin/networksetup';
    final install = "echo '$rule' > /etc/sudoers.d/lanway && "
        'chmod 440 /etc/sudoers.d/lanway && '
        'visudo -cf /etc/sudoers.d/lanway || rm -f /etc/sudoers.d/lanway';

    final res = await Process.run('osascript', [
      '-e',
      'do shell script ${_appleScriptString(install)} with administrator privileges '
          'with prompt "Lanway needs permission once to route your traffic."',
    ]);
    if (res.exitCode != 0) {
      throw Exception('Could not set up the proxy helper. ${res.stderr}');
    }
  }

  /// Quotes a shell command as an AppleScript string literal.
  String _appleScriptString(String s) {
    final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
