import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/connect_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/license_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: LanwayManagerApp()));
}

class LanwayManagerApp extends ConsumerWidget {
  const LanwayManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'Lanway Manager',
      debugShowCheckedModeBanner: false,
      theme: buildLanwayTheme(),
      scrollBehavior: const _NoScrollbarBehavior(),
      routerConfig: router,
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  final listenable = _ConnectionListenable(ref);
  return GoRouter(
    initialLocation: '/connect',
    refreshListenable: listenable,
    redirect: (context, state) {
      final connected = ref.read(connectionProvider) != null;
      final atConnect = state.matchedLocation == '/connect';
      // Not connected → can only be on the home/chooser screen. When connected,
      // the home screen stays reachable (it shows your current server).
      if (!connected && !atConnect) return '/connect';
      return null;
    },
    routes: [
      GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/license', builder: (_, _) => const LicenseScreen()),
      GoRoute(
        path: '/share/:id',
        builder: (_, state) => ShareScreen(userId: state.pathParameters['id']!),
      ),
    ],
  );
});

/// Bridges the Riverpod connection state into a Listenable for go_router so the
/// app navigates automatically when the user connects or disconnects.
class _ConnectionListenable extends ChangeNotifier {
  _ConnectionListenable(Ref ref) {
    ref.listen(connectionProvider, (_, _) => notifyListeners());
  }
}

/// Hides the always-on desktop scrollbars while keeping scrolling smooth.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}
