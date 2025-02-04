import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class AppTray extends TrayListener {
  void initSystemTray() async {
    await trayManager.setIcon('assets/icon.png');

    List<MenuItem> menuItems = [
      MenuItem(
        key: 'show',
        label: 'Show App',
      ),
      MenuItem(
        key: 'hide',
        label: 'Hide App',
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit',
        label: 'Exit',
      ),
    ];

    Menu menu = Menu(items: menuItems);

    await trayManager.setContextMenu(menu);
    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'hide':
        await windowManager.hide();
        break;
      case 'exit':
        await windowManager.destroy();
        break;
    }
  }
}
