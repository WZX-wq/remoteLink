import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/mobile/pages/account_page.dart';
import 'package:flutter_hbb/mobile/pages/recent_connections_page.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/widgets/mobile_bottom_navigation_safe_area.dart';
import 'package:flutter_hbb/web/settings_page.dart';
import 'package:get/get.dart';
import '../../common.dart';
import '../../common/widgets/login.dart';
import '../../consts.dart';
import '../../common/kq_theme.dart';
import '../../models/platform_model.dart';
import '../../models/state_model.dart';
import 'page_shape.dart';
import 'connection_page.dart';

class HomePage extends StatefulWidget {
  static final homeKey = GlobalKey<HomePageState>();

  HomePage() : super(key: homeKey);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  var _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;
  final List<PageShape> _pages = [];
  bool get isChatPageCurrentTab => false;

  void showChatPage() {}

  void refreshPages() {
    setState(() {
      initPages();
    });
  }

  @override
  void initState() {
    super.initState();
    initPages();
    kqRegisterMobileLanguageListener(refreshPages);
  }

  @override
  void dispose() {
    kqUnregisterMobileLanguageListener(refreshPages);
    super.dispose();
  }

  void initPages() {
    _pages.clear();
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(
        appBarActions: [],
      ));
    }
    if (!bind.isOutgoingOnly()) {
      _pages.add(ServerPage());
    }
    if (!bind.isIncomingOnly()) {
      _pages.add(RecentConnectionsPage());
    }
    _pages.add(AccountPage());
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Obx(() {
      kqMobileLanguageEpoch.value;
      return WillPopScope(
          onWillPop: () async {
            if (_selectedIndex != 0) {
              setState(() {
                _selectedIndex = 0;
              });
            } else {
              return true;
            }
            return false;
          },
          child: Scaffold(
            extendBody: false,
            backgroundColor: q.surface,
            bottomNavigationBar: MobileBottomNavigationSafeArea(
              isIOS: isIOS,
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                decoration: BoxDecoration(
                  color: q.panelStrong.withOpacity(q.isDark ? 0.92 : 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: q.line),
                  boxShadow: [
                    BoxShadow(
                      color: q.shadow,
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      final selected = states.contains(WidgetState.selected);
                      return IconThemeData(
                        color: selected ? q.primary : q.muted,
                        size: 26,
                      );
                    }),
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      final selected = states.contains(WidgetState.selected);
                      return TextStyle(
                        color: selected ? q.ink : q.muted,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                      );
                    }),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: NavigationBar(
                      key: navigationBarKey,
                      height: 68,
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      indicatorColor: q.primary.withOpacity(0.16),
                      selectedIndex: _selectedIndex,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: _pages
                          .map((page) => NavigationDestination(
                                icon: page.icon,
                                selectedIcon: page.icon,
                                label: _mobileNavigationLabel(page.title),
                              ))
                          .toList(),
                      onDestinationSelected: (index) => setState(() {
                        if (_selectedIndex != index) {
                          _selectedIndex = index;
                        }
                      }),
                    ),
                  ),
                ),
              ),
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: q.pageGradient,
                ),
              ),
              child: SafeArea(
                top: true,
                bottom: false,
                child: _pages.elementAt(_selectedIndex),
              ),
            ),
          ));
    });
  }
}

String _mobileNavigationLabel(String title) {
  final knownTitles = {
    'Connection',
    'Remote connection',
    'Recent devices',
    'Recent connections',
    'Share screen',
    'Me',
    '我的',
    '连接',
    '最近连接',
    '共享屏幕',
    '远程连接',
  };
  if (!knownTitles.contains(title)) return title;
  if (!kqUiPrefersChinese()) {
    switch (title) {
      case '我的':
        return translate('Me');
      case '连接':
      case '远程连接':
        return translate('Connection');
      case '最近连接':
        return translate('Recent connections');
      case '共享屏幕':
        return translate('Share screen');
      default:
        return translate(title);
    }
  }
  switch (title) {
    case 'Connection':
    case 'Remote connection':
      return '连接';
    case 'Recent devices':
    case 'Recent connections':
      return '最近连接';
    case 'Share screen':
      return '共享屏幕';
    case 'Me':
      return '我的';
    default:
      return title;
  }
}

class WebHomePage extends StatelessWidget {
  final connectionPage =
      ConnectionPage(appBarActions: <Widget>[const WebSettingsPage()]);

  @override
  Widget build(BuildContext context) {
    stateGlobal.isInMainPage = true;
    unawaited(handleUnilink(context));
    return Scaffold(
      // backgroundColor: MyTheme.grayBg,
      appBar: AppBar(
        centerTitle: true,
        title: Text("${bind.mainGetAppNameSync()} (Preview)"),
        actions: connectionPage.appBarActions,
      ),
      body: connectionPage,
    );
  }

  Future<void> handleUnilink(BuildContext context) async {
    if (webInitialLink.isEmpty) {
      return;
    }
    final link = webInitialLink;
    webInitialLink = '';
    final splitter = ["/#/", "/#", "#/", "#"];
    var fakelink = '';
    for (var s in splitter) {
      if (link.contains(s)) {
        var list = link.split(s);
        if (list.length < 2 || list[1].isEmpty) {
          return;
        }
        list.removeAt(0);
        fakelink = "rustdesk://${list.join(s)}";
        break;
      }
    }
    if (fakelink.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(fakelink);
    if (uri == null) {
      return;
    }
    final args = urlLinkToCmdArgs(uri);
    if (args == null || args.isEmpty) {
      return;
    }
    bool isFileTransfer = false;
    bool isViewCamera = false;
    bool isTerminal = false;
    String? id;
    String? password;
    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--connect':
        case '--play':
          id = args[i + 1];
          i++;
          break;
        case '--file-transfer':
          isFileTransfer = true;
          id = args[i + 1];
          i++;
          break;
        case '--view-camera':
          if (!kShowViewCameraConnectAction) {
            i++;
            break;
          }
          isViewCamera = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal':
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--terminal-admin':
          setEnvTerminalAdmin();
          isTerminal = true;
          id = args[i + 1];
          i++;
          break;
        case '--password':
          password = args[i + 1];
          i++;
          break;
        default:
          break;
      }
    }
    if (id != null) {
      if (!gFFI.userModel.isLogin) {
        showToast(translate('Please login before remote connection'));
        final loggedIn = await loginDialog();
        if (loggedIn != true || !gFFI.userModel.isLogin) {
          showToast(translate('Not logged in, remote connection unavailable'));
          return;
        }
      }
      connect(context, id,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTerminal: isTerminal,
          password: password);
    }
  }
}
