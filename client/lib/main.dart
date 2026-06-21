import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/add_server_screen.dart';
import 'screens/home_screen.dart';
import 'screens/license_screen.dart';
import 'screens/server_list_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/speed_test_screen.dart';
import 'dns_settings.dart';
import 'storage.dart';
import 'theme.dart';
import 'tray_service.dart';
import 'vless.dart';
import 'vpn_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (LanwayTray.supported) {
    await windowManager.ensureInitialized();
  }
  runApp(const ProviderScope(child: LanwayClientApp()));
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/servers', builder: (_, _) => const ServerListScreen()),
    GoRoute(path: '/add', builder: (_, _) => const AddServerScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/license', builder: (_, _) => const LicenseScreen()),
    GoRoute(path: '/speedtest', builder: (_, _) => const SpeedTestScreen()),
  ],
);

class LanwayClientApp extends ConsumerStatefulWidget {
  const LanwayClientApp({super.key});
  @override
  ConsumerState<LanwayClientApp> createState() => _LanwayClientAppState();
}

class _LanwayClientAppState extends ConsumerState<LanwayClientApp> {
  final _appLinks = AppLinks();
  LanwayTray? _tray;

  @override
  void initState() {
    super.initState();
    _listenForDeepLinks();
    _setupTray();
  }

  /// Sets up the menu-bar icon (desktop only) and keeps it in sync with the
  /// connection state.
  Future<void> _setupTray() async {
    if (!LanwayTray.supported) return;
    _tray = LanwayTray(
      onOpen: () async {
        await windowManager.show();
        await windowManager.focus();
      },
      onToggle: () {
        final vpn = ref.read(vpnControllerProvider);
        final ctrl = ref.read(vpnControllerProvider.notifier);
        if (vpn.isConnected || vpn.stage == VpnStage.connecting) {
          ctrl.disconnect();
        } else {
          final server = ref.read(activeServerProvider);
          if (server != null) {
            ctrl.connect(server, dns: ref.read(dnsServersProvider));
          } else {
            windowManager.show();
          }
        }
      },
      onQuit: () => exit(0),
    );
    await _tray!.init();
    // Reflect connection state in the tray icon + menu.
    ref.listenManual(vpnControllerProvider, (_, next) {
      _tray?.setConnected(next.stage == VpnStage.connected);
    });
  }

  @override
  void dispose() {
    _tray?.dispose();
    super.dispose();
  }

  /// Handles `lanway://add?config=…` deep links, both cold-start and while running.
  Future<void> _listenForDeepLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleLink(initial.toString());
    _appLinks.uriLinkStream.listen((uri) => _handleLink(uri.toString()));
  }

  Future<void> _handleLink(String raw) async {
    final parsed = parseShareLink(raw);
    if (parsed == null) return;
    final server = await ref.read(serversProvider.notifier).add(parsed.name, parsed.vless);
    await ref.read(activeServerIdProvider.notifier).set(server.id);
    _router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Lanway',
      debugShowCheckedModeBanner: false,
      theme: buildLanwayTheme(),
      routerConfig: _router,
    );
  }
}
