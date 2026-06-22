import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'singbox_config.dart';

/// Runs the VPN tunnel on desktop.
///
/// macOS uses a full **TUN** tunnel powered by a bundled sing-box core: a
/// virtual interface captures *all* traffic — TCP **and UDP/QUIC** — and routes
/// it through VLESS + REALITY to the Lanway server. Nothing leaks around the
/// tunnel, so apps like Messenger (whose realtime traffic is QUIC) work, and a
/// censored local network can't see or fall back onto the original path. This
/// matches how Outline and the Lanway mobile client tunnel.
///
/// Windows still uses the bundled Xray core as a system proxy (TUN is a separate
/// follow-up there).
class DesktopVpn {
  bool _winActive = false;
  bool _macActive = false;

  bool get isActive => _winActive || _macActive;

  // ── macOS privileged helper layout (root-owned, so it can't be tampered
  // with for a privilege-escalation). The helper runs/stops the core as root. ──
  static const _macHelperDir = '/usr/local/lib/lanway';
  static const _macCore = '$_macHelperDir/lanway-core';
  static const _macHelper = '$_macHelperDir/lanway-helper';
  static const _macConfig = '$_macHelperDir/config.json';

  Future<void> connect(String vlessLink, {List<String> dns = const []}) async {
    if (Platform.isMacOS) return _connectMacTun(vlessLink, dns: dns);
    if (Platform.isWindows) return _connectWindowsTun(vlessLink, dns: dns);
    throw Exception('Desktop VPN is only supported on macOS and Windows.');
  }

  Future<void> disconnect() async {
    if (Platform.isMacOS) return _disconnectMacTun();
    if (Platform.isWindows) return _disconnectWindowsTun();
  }

  // ───────────────────────────── macOS (TUN) ────────────────────────────────

  Future<void> _connectMacTun(String vlessLink, {List<String> dns = const []}) async {
    final dir = await getApplicationSupportDirectory();
    final bundledCore = await _extractMacCore(dir);
    final configJson = buildSingBoxConfig(vlessLink, dns: dns.isEmpty ? const ['1.1.1.1'] : dns);

    // One-time admin prompt: install the core + helper to a root-owned dir and a
    // narrow sudoers rule, so every later connect/disconnect is password-free.
    await _ensureMacHelper(bundledCore);

    // Write the config to the root-owned dir (via the helper) and start.
    final start = await Process.run('sudo', ['-n', _macHelper, 'start', configJson]);
    if (start.exitCode != 0) {
      throw Exception('Could not start the tunnel. ${start.stderr}'.trim());
    }

    // Give it a moment, then confirm it actually came up (didn't crash on a bad
    // config / signing / permission).
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final status = await Process.run('sudo', ['-n', _macHelper, 'status']);
    if (status.exitCode != 0) {
      final log = await Process.run('sudo', ['-n', _macHelper, 'log']);
      throw Exception('The tunnel did not start.\n${log.stdout}'.trim());
    }
    _macActive = true;
  }

  Future<void> _disconnectMacTun() async {
    try {
      await Process.run('sudo', ['-n', _macHelper, 'stop']);
    } catch (_) {/* best effort */}
    _macActive = false;
  }

  /// Extracts the bundled sing-box core to app support and returns its path.
  Future<String> _extractMacCore(Directory dir) async {
    final out = File('${dir.path}/lanway-core');
    final data = await _loadAsset('assets/bin/singbox_macos');
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await Process.run('chmod', ['+x', out.path]);
    return out.path;
  }

  /// Installs the root-owned core + helper + sudoers rule (once). The helper is
  /// the only thing granted passwordless sudo, and it lives in a root-owned dir
  /// so it can't be swapped out. Re-runs the copy when the core changed.
  Future<void> _ensureMacHelper(String bundledCore) async {
    // Already installed and current? sudo -n succeeds without a password and the
    // installed core matches the bundled one.
    final probe = await Process.run('sudo', ['-n', _macHelper, 'version']);
    if (probe.exitCode == 0) {
      final same = await Process.run('cmp', ['-s', bundledCore, _macCore]);
      if (same.exitCode == 0) return;
    }

    final user = Platform.environment['USER'] ??
        (await Process.run('whoami', [])).stdout.toString().trim();

    // Build a single privileged shell command. The helper script is written via
    // base64 (not a heredoc) so it survives being joined into one `&&` line —
    // a heredoc would swallow the commands after it, including the sudoers rule.
    final helperB64 = base64.encode(utf8.encode(_macHelperScript));
    final sudoers = '$user ALL=(root) NOPASSWD: $_macHelper';
    final install = [
      'mkdir -p $_macHelperDir',
      'install -m 0755 -o root -g wheel ${_sh(bundledCore)} $_macCore',
      '(xattr -dr com.apple.quarantine $_macCore 2>/dev/null || true)',
      'printf %s ${_sh(helperB64)} | /usr/bin/base64 -D > $_macHelper',
      'chown root:wheel $_macHelper',
      'chmod 0755 $_macHelper',
      'echo ${_sh(sudoers)} > /etc/sudoers.d/lanway',
      'chmod 0440 /etc/sudoers.d/lanway',
      'visudo -cf /etc/sudoers.d/lanway || rm -f /etc/sudoers.d/lanway',
    ].join(' && ');

    final res = await Process.run('osascript', [
      '-e',
      'do shell script ${_appleScriptString(install)} with administrator privileges '
          'with prompt "Lanway needs permission once to route your traffic."',
    ]);
    if (res.exitCode != 0) {
      throw Exception('Could not set up the tunnel helper. ${res.stderr}'.trim());
    }
  }

  /// The root-owned helper script: start/stop/status the core as root. Keeping
  /// this tiny and fixed (only the core + a caller-supplied config) keeps the
  /// passwordless-sudo surface minimal.
  static const _macHelperScript = '''#!/bin/sh
CORE=$_macCore
CONFIG=$_macConfig
PIDFILE=/var/run/lanway-core.pid
LOG=/var/log/lanway-core.log
case "\$1" in
  start)
    printf '%s' "\$2" > "\$CONFIG"
    "\$CORE" run -c "\$CONFIG" >"\$LOG" 2>&1 &
    echo \$! > "\$PIDFILE"
    ;;
  stop)
    [ -f "\$PIDFILE" ] && kill "\$(cat "\$PIDFILE")" 2>/dev/null
    rm -f "\$PIDFILE"
    pkill -f "\$CORE" 2>/dev/null
    exit 0
    ;;
  status)
    [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null
    ;;
  log)  tail -n 30 "\$LOG" 2>/dev/null ;;
  version) "\$CORE" version 2>/dev/null ;;
esac
''';

  // ───────────────────────────── Windows (TUN) ──────────────────────────────
  // Mirrors the macOS TUN approach with sing-box. A one-time elevated step
  // registers a Scheduled Task that runs the core with highest privileges, so
  // later connects/disconnects don't prompt for UAC. NOTE: this path is written
  // blind (no Windows test environment yet) and will likely need a test-fix
  // pass on a real Windows machine — see $_winCoreDir\\core.log to debug.

  static const _winTask = 'LanwayTunnel';
  static const _winCoreDir = r'C:\ProgramData\Lanway';
  static const _winCore = r'C:\ProgramData\Lanway\lanway-core.exe';
  static const _winLog = r'C:\ProgramData\Lanway\core.log';

  Future<void> _connectWindowsTun(String vlessLink, {List<String> dns = const []}) async {
    final dir = await getApplicationSupportDirectory();
    final coreSrc = await _extractWinCore(dir);
    final configFile = File('${dir.path}\\lanway-singbox.json');
    await configFile.writeAsString(
      buildSingBoxConfig(vlessLink, dns: dns.isEmpty ? const ['1.1.1.1'] : dns, logPath: _winLog),
    );

    await _ensureWindowsHelper(coreSrc, configFile.path);

    final run = await Process.run('schtasks', ['/run', '/tn', _winTask]);
    if (run.exitCode != 0) {
      throw Exception('Could not start the tunnel. ${run.stdout}${run.stderr}'.trim());
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final q = await Process.run('schtasks', ['/query', '/tn', _winTask, '/fo', 'list', '/v']);
    if (!q.stdout.toString().toLowerCase().contains('running')) {
      throw Exception('The tunnel did not start. See $_winCoreDir\\core.log');
    }
    _winActive = true;
  }

  Future<void> _disconnectWindowsTun() async {
    try {
      await Process.run('schtasks', ['/end', '/tn', _winTask]);
    } catch (_) {/* best effort */}
    _winActive = false;
  }

  Future<String> _extractWinCore(Directory dir) async {
    final out = File('${dir.path}\\lanway-core.exe');
    final data = await _loadAsset('assets/bin/singbox_windows.exe');
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out.path;
  }

  /// One-time elevated setup: copy the core into a machine-wide dir and register
  /// a highest-privileges Scheduled Task, so connecting later needs no UAC.
  Future<void> _ensureWindowsHelper(String coreSrc, String configPath) async {
    final probe = await Process.run('schtasks', ['/query', '/tn', _winTask]);
    if (probe.exitCode == 0) {
      try {
        await File(coreSrc).copy(_winCore); // keep the installed core current
      } catch (_) {/* in use or no perms — fine */}
      return;
    }

    final dir = await getApplicationSupportDirectory();
    final ps1 = File('${dir.path}\\lanway-setup.ps1');
    final script = "\$ErrorActionPreference = 'Stop'\n"
        "New-Item -ItemType Directory -Force -Path '$_winCoreDir' | Out-Null\n"
        "Copy-Item -Force '$coreSrc' '$_winCore'\n"
        "\$action = New-ScheduledTaskAction -Execute '$_winCore' "
        "-Argument 'run -c \"$configPath\"' -WorkingDirectory '$_winCoreDir'\n"
        "\$principal = New-ScheduledTaskPrincipal -UserId \$env:USERNAME -RunLevel Highest -LogonType Interactive\n"
        "\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries "
        "-DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew\n"
        "Register-ScheduledTask -TaskName '$_winTask' -Action \$action "
        "-Principal \$principal -Settings \$settings -Force | Out-Null\n";
    await ps1.writeAsString(script);

    // Launch an elevated PowerShell (UAC once) to run the setup script.
    final res = await Process.run('powershell', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
      "\$p = Start-Process powershell "
          "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${ps1.path}' "
          "-Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit \$p.ExitCode",
    ]);
    if (res.exitCode != 0) {
      throw Exception('Could not set up the tunnel helper. ${res.stderr}'.trim());
    }
  }

  // ───────────────────────────────── helpers ────────────────────────────────

  Future<ByteData> _loadAsset(String path) async {
    try {
      return await rootBundle.load(path);
    } catch (_) {
      throw Exception('The VPN core is not bundled in this build ($path). '
          'Add the core binary to assets/bin/ and rebuild.');
    }
  }

  /// Single-quotes a string for safe use inside a /bin/sh command.
  String _sh(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Quotes a shell command as an AppleScript string literal.
  String _appleScriptString(String s) {
    final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
