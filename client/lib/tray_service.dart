import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

/// Lives in the macOS/Windows menu bar: shows connection state and offers
/// Open / Connect-Disconnect / Quit. No-op on mobile.
class LanwayTray with TrayListener {
  final void Function() onOpen;
  final void Function() onToggle;
  final void Function() onQuit;

  LanwayTray({required this.onOpen, required this.onToggle, required this.onQuit});

  static bool get supported => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  bool _connected = false;

  Future<void> init() async {
    if (!supported) return;
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray/tray_off.png', isTemplate: false);
    await trayManager.setToolTip('Lanway — Disconnected');
    await _rebuildMenu();
  }

  Future<void> setConnected(bool connected) async {
    if (!supported || connected == _connected) return;
    _connected = connected;
    await trayManager.setIcon(
      connected ? 'assets/tray/tray_on.png' : 'assets/tray/tray_off.png',
      isTemplate: false,
    );
    await trayManager.setToolTip(connected ? 'Lanway — Connected' : 'Lanway — Disconnected');
    await _rebuildMenu();
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        key: 'status',
        label: _connected ? '● Connected' : '○ Disconnected',
        disabled: true,
      ),
      MenuItem.separator(),
      MenuItem(key: 'open', label: 'Open Lanway'),
      MenuItem(key: 'toggle', label: _connected ? 'Disconnect' : 'Connect'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit Lanway'),
    ]));
  }

  void dispose() {
    if (supported) trayManager.removeListener(this);
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        onOpen();
      case 'toggle':
        onToggle();
      case 'quit':
        onQuit();
    }
  }
}
