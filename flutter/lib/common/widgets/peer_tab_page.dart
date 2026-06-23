import 'dart:ui' as ui;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/address_book.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/my_group.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/desktop/widgets/material_mod_popup_menu.dart'
    as mod_menu;
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../models/platform_model.dart';

class PeerTabPage extends StatefulWidget {
  const PeerTabPage({Key? key}) : super(key: key);
  @override
  State<PeerTabPage> createState() => _PeerTabPageState();
}

class _TabEntry {
  final Widget widget;
  final Function({dynamic hint})? load;
  _TabEntry(this.widget, [this.load]);
}

EdgeInsets? _menuPadding() {
  return (isDesktop || isWebDesktop) ? kDesktopMenuPadding : null;
}

String _kqPeerTabText(String key) {
  if (!kqUiPrefersChinese()) {
    return translate(key);
  }
  switch (key) {
    case 'Device groups':
      return '设备分组';
    case 'Search device ID or name':
      return '输入设备号或名称搜索';
    default:
      return translate(key);
  }
}

class _PeerTabPageState extends State<PeerTabPage>
    with SingleTickerProviderStateMixin {
  final List<_TabEntry> entries = [
    _TabEntry(RecentPeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(FavoritePeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(DiscoveredPeersView(
      menuPadding: _menuPadding(),
    )),
    _TabEntry(
        AddressBook(
          menuPadding: _menuPadding(),
        ),
        ({dynamic hint}) => gFFI.abModel.pullAb(
            force: hint == null ? ForcePullAb.listAndCurrent : null,
            quiet: false)),
    _TabEntry(
      MyGroup(
        menuPadding: _menuPadding(),
      ),
      ({dynamic hint}) => gFFI.groupModel.pull(force: hint == null),
    ),
  ];
  RelativeRect? mobileTabContextMenuPos;
  double _recentRefreshTurns = 0;

  final isOptVisiableFixed = isOptionFixed(kOptionPeerTabVisible);

  _PeerTabPageState() {
    _loadLocalOptions();
  }

  void _loadLocalOptions() {
    final uiType = bind.getLocalFlutterOption(k: kOptionPeerCardUiType);
    if (uiType != '') {
      peerCardUiType.value = int.parse(uiType) == 0
          ? PeerUiType.grid
          : int.parse(uiType) == 1
              ? PeerUiType.tile
              : PeerUiType.list;
    }
    hideAbTagsPanel.value =
        bind.mainGetLocalOption(key: kOptionHideAbTagsPanel) == 'Y';
  }

  Future<void> handleTabSelection(int tabIndex) async {
    if (tabIndex < entries.length) {
      if (tabIndex != gFFI.peerTabModel.currentTab) {
        gFFI.peerTabModel.setCurrentTabCachedPeers([]);
      }
      gFFI.peerTabModel.setCurrentTab(tabIndex);
      entries[tabIndex].load?.call(hint: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    Widget selectionWrap(Widget widget) {
      return model.multiSelectionMode ? createMultiSelectionBar(model) : widget;
    }

    return Column(
      textBaseline: TextBaseline.ideographic,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() => SizedBox(
              height: stateGlobal.isPortrait.isTrue
                  ? _mobilePortraitToolbarHeight(model)
                  : 44,
              child: Container(
                margin: stateGlobal.isPortrait.isTrue
                    ? const EdgeInsets.fromLTRB(0, 16, 0, 0)
                    : const EdgeInsets.fromLTRB(14, 12, 14, 0),
                padding: stateGlobal.isPortrait.isTrue
                    ? EdgeInsets.zero
                    : const EdgeInsets.symmetric(horizontal: 4),
                child: selectionWrap(stateGlobal.isPortrait.isTrue
                    ? _buildPortraitToolbar(context)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          visibleContextMenuListener(_createSwitchBar(context)),
                          const Spacer(),
                          ..._landscapeRightActions(context)
                        ],
                      )),
              ),
            )),
        _createPeersView(),
      ],
    );
  }

  Widget _buildPortraitToolbar(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final q = KqTheme.of(context);
    final count = model.currentTabCachedPeers.length;
    final isMobileRecentPage = _isMobileRecentPage(model);
    final showMobileTabTitle = !_shouldHideMobileRecentTabTitle(model);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: PeerSearchBar(expanded: true),
            ),
            const SizedBox(width: 12),
            _mobileToolbarButton(
              context,
              icon: Icons.refresh_rounded,
              tooltip: translate('Refresh'),
              rotationTurns: _recentRefreshTurns,
              onTap: () {
                setState(() => _recentRefreshTurns += 1);
                if (gFFI.peerTabModel.currentTab < entries.length) {
                  entries[gFFI.peerTabModel.currentTab].load?.call();
                }
              },
            ),
            if (!isMobileRecentPage) ...[
              const SizedBox(width: 10),
              _mobileToolbarButton(
                context,
                icon: Icons.tune_rounded,
                tooltip: _kqPeerTabText('Device groups'),
                onTap: _showMobileTabSelector,
              ),
            ],
          ],
        ),
        if (showMobileTabTitle) const SizedBox(height: 18),
        if (showMobileTabTitle)
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _showMobileTabSelector,
            onLongPress: mobileShowTabVisibilityMenu,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: q.muted, size: 22),
                const SizedBox(width: 4),
                Text(
                  '${model.tabTooltip(model.currentTab)}($count)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  double _mobilePortraitToolbarHeight(PeerTabModel model) {
    if (model.multiSelectionMode) return 102;
    return _shouldHideMobileRecentTabTitle(model) ? 64 : 102;
  }

  bool _shouldHideMobileRecentTabTitle(PeerTabModel model) {
    return _isMobileRecentPage(model);
  }

  bool _isMobileRecentPage(PeerTabModel model) {
    return isMobile &&
        stateGlobal.isPortrait.isTrue &&
        model.currentTab == PeerTabIndex.recent.index;
  }

  Widget _mobileToolbarButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double rotationTurns = 0,
  }) {
    final q = KqTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: q.panelStrong.withOpacity(q.isDark ? 0.82 : 0.96),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: q.line),
            boxShadow: [
              BoxShadow(
                color: q.shadow.withOpacity(q.isDark ? 0.36 : 0.7),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: rotationTurns,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: Icon(icon, color: q.primary, size: 24),
          ),
        ),
      ),
    );
  }

  void _showMobileTabSelector() {
    final model = gFFI.peerTabModel;
    final visibleTabs = model.visibleEnabledOrderedIndexs;
    if (visibleTabs.isEmpty) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: KqTheme.of(context).panelStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final q = KqTheme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kqPeerTabText('Device groups'),
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...visibleTabs.map((index) {
                  final selected = model.currentTab == index;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: Icon(
                      model.tabIcon(index),
                      color: selected ? q.primary : q.muted,
                    ),
                    title: Text(
                      model.tabTooltip(index),
                      style: TextStyle(
                        color: selected ? q.primaryDeep : q.ink,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle_rounded, color: q.primary)
                        : null,
                    selected: selected,
                    selectedTileColor: q.primary.withOpacity(0.08),
                    onTap: () async {
                      Navigator.pop(context);
                      await handleTabSelection(index);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _createSwitchBar(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    final q = KqTheme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: q.panelStrong.withOpacity(q.isDark ? 0.82 : 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            color: q.primary,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            model.tabTooltip(model.currentTab),
            style: TextStyle(
              color: q.ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _createPeersView() {
    final model = Provider.of<PeerTabModel>(context);
    final q = KqTheme.of(context);
    final isPortrait = stateGlobal.isPortrait.isTrue;
    Widget child;
    if (model.visibleEnabledOrderedIndexs.isEmpty) {
      child = visibleContextMenuListener(Row(
        children: [Expanded(child: InkWell())],
      ));
    } else {
      if (model.visibleEnabledOrderedIndexs.contains(model.currentTab)) {
        child = entries[model.currentTab].widget;
      } else {
        debugPrint("should not happen! currentTab not in visibleIndexs");
        Future.delayed(Duration.zero, () {
          model.setCurrentTab(model.visibleEnabledOrderedIndexs[0]);
        });
        child = entries[0].widget;
      }
    }
    return Expanded(
      child: Container(
        margin: isPortrait
            ? const EdgeInsets.fromLTRB(0, 8, 0, 14)
            : EdgeInsets.fromLTRB(
                14,
                (isDesktop || isWebDesktop) ? 12.0 : 6.0,
                14,
                14,
              ),
        padding: isPortrait ? EdgeInsets.zero : const EdgeInsets.all(12),
        decoration: isPortrait
            ? null
            : BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: q.workSurfaceGradient,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: q.line),
              ),
        child: child,
      ),
    );
  }

  Widget _createRefresh(
      {required PeerTabIndex index, required RxBool loading}) {
    final model = Provider.of<PeerTabModel>(context);
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Offstage(
      offstage: model.currentTab != index.index,
      child: Tooltip(
        message: translate('Refresh'),
        child: RefreshWidget(
            onPressed: () {
              if (gFFI.peerTabModel.currentTab < entries.length) {
                entries[gFFI.peerTabModel.currentTab].load?.call();
              }
            },
            spinning: loading,
            child: RotatedBox(
                quarterTurns: 2,
                child: Icon(
                  Icons.refresh,
                  size: 18,
                  color: textColor,
                ))),
      ),
    );
  }

  Widget _createPeerViewTypeSwitch(BuildContext context) {
    return PeerViewDropdown();
  }

  Widget _createMultiSelection() {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
      toolTip: translate('Select'),
      context: context,
      onTap: () {
        model.setMultiSelectionMode(true);
        if (isMobile && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: SvgPicture.asset(
        "assets/checkbox-outline.svg",
        width: 18,
        height: 18,
        colorFilter: svgColor(textColor),
      ),
    );
  }

  void mobileShowTabVisibilityMenu() {
    final model = gFFI.peerTabModel;
    final items = List<PopupMenuItem>.empty(growable: true);
    for (int i = 0; i < PeerTabModel.maxTabCount; i++) {
      if (!model.isEnabled[i]) continue;
      items.add(PopupMenuItem(
        height: kMinInteractiveDimension * 0.8,
        onTap: isOptVisiableFixed
            ? null
            : () => model.setTabVisible(i, !model.isVisibleEnabled[i]),
        enabled: !isOptVisiableFixed,
        child: Row(
          children: [
            Checkbox(
                value: model.isVisibleEnabled[i],
                onChanged: isOptVisiableFixed
                    ? null
                    : (_) {
                        model.setTabVisible(i, !model.isVisibleEnabled[i]);
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      }),
            Expanded(child: Text(model.tabTooltip(i))),
          ],
        ),
      ));
    }
    if (mobileTabContextMenuPos != null) {
      showMenu(
          context: context, position: mobileTabContextMenuPos!, items: items);
    }
  }

  Widget visibleContextMenuListener(Widget child) {
    if (!(isDesktop || isWebDesktop)) {
      return GestureDetector(
        onLongPressDown: (e) {
          final x = e.globalPosition.dx;
          final y = e.globalPosition.dy;
          mobileTabContextMenuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onLongPressUp: () {
          mobileShowTabVisibilityMenu();
        },
        child: child,
      );
    } else {
      return Listener(
          onPointerDown: (e) {
            if (e.kind != ui.PointerDeviceKind.mouse) {
              return;
            }
            if (e.buttons == 2) {
              showRightMenu(
                (CancelFunc cancelFunc) {
                  return visibleContextMenu(cancelFunc);
                },
                target: e.position,
              );
            }
          },
          child: child);
    }
  }

  Widget visibleContextMenu(CancelFunc cancelFunc) {
    final model = Provider.of<PeerTabModel>(context);
    final menu = List<MenuEntrySwitchSync>.empty(growable: true);
    for (int i = 0; i < model.orders.length; i++) {
      int tabIndex = model.orders[i];
      if (tabIndex < 0 || tabIndex >= PeerTabModel.maxTabCount) continue;
      if (!model.isEnabled[tabIndex]) continue;
      menu.add(MenuEntrySwitchSync(
          switchType: SwitchType.scheckbox,
          text: model.tabTooltip(tabIndex),
          currentValue: model.isVisibleEnabled[tabIndex],
          setter: (show) async {
            model.setTabVisible(tabIndex, show);
            // Do not hide the current menu (checkbox)
            // cancelFunc();
          },
          enabled: (!isOptVisiableFixed).obs));
    }
    return mod_menu.PopupMenu(
        items: menu
            .map((entry) => entry.build(
                context,
                const MenuConfig(
                  commonColor: MyTheme.accent,
                  height: 20.0,
                  dividerHeight: 12.0,
                )))
            .expand((i) => i)
            .toList());
  }

  Widget createMultiSelectionBar(PeerTabModel model) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Offstage(
          offstage: model.selectedPeers.isEmpty,
          child: Row(
            children: [
              deleteSelection(),
              addSelectionToFav(),
              addSelectionToAb(),
              editSelectionTags(),
            ],
          ),
        ),
        Row(
          children: [
            selectionCount(model.selectedPeers.length),
            selectAll(model),
            closeSelection(),
          ],
        )
      ],
    );
  }

  Widget deleteSelection() {
    final model = Provider.of<PeerTabModel>(context);
    if (model.currentTab == PeerTabIndex.group.index) {
      return Offstage();
    }
    return _hoverAction(
        context: context,
        toolTip: translate('Delete'),
        onTap: () {
          onSubmit() async {
            final peers = model.selectedPeers;
            switch (model.currentTab) {
              case 0:
                for (var p in peers) {
                  await deleteKqRecentPeer(p.id);
                }
                bind.mainLoadRecentPeers();
                break;
              case 1:
                final favs = (await bind.mainGetFav()).toList();
                peers.map((p) {
                  favs.remove(p.id);
                }).toList();
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
                bind.mainLoadRecentPeers();
                break;
              case 2:
                for (var p in peers) {
                  await bind.mainRemoveDiscovered(id: p.id);
                }
                bind.mainLoadLanPeers();
                break;
              case 3:
                await gFFI.abModel.deletePeers(peers.map((p) => p.id).toList());
                break;
              default:
                break;
            }
            gFFI.peerTabModel.setMultiSelectionMode(false);
            if (model.currentTab != 3) showToast(translate('Successful'));
          }

          deleteConfirmDialog(onSubmit, translate('Delete'));
        },
        child: Icon(Icons.delete, color: Colors.red));
  }

  Widget addSelectionToFav() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage:
          model.currentTab != PeerTabIndex.recent.index, // show based on recent
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to Favorites'),
        onTap: () async {
          final peers = model.selectedPeers;
          final favs = (await bind.mainGetFav()).toList();
          for (var p in peers) {
            if (!favs.contains(p.id)) {
              favs.add(p.id);
            }
          }
          await bind.mainStoreFav(favs: favs);
          bind.mainLoadFavPeers();
          bind.mainLoadRecentPeers();
          model.setMultiSelectionMode(false);
          showToast(translate('Successful'));
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.fav.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget addSelectionToAb() {
    final model = Provider.of<PeerTabModel>(context);
    final addressbooks = gFFI.abModel.addressBooksCanWrite();
    if (model.currentTab == PeerTabIndex.ab.index) {
      addressbooks.remove(gFFI.abModel.currentName.value);
    }
    return Offstage(
      offstage: !gFFI.userModel.isLogin || addressbooks.isEmpty,
      child: _hoverAction(
        context: context,
        toolTip: translate('Add to address book'),
        onTap: () {
          final peers = model.selectedPeers.map((e) => Peer.copy(e)).toList();
          addPeersToAbDialog(peers);
          model.setMultiSelectionMode(false);
        },
        child: Icon(PeerTabModel.icons[PeerTabIndex.ab.index]),
      ).marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget editSelectionTags() {
    final model = Provider.of<PeerTabModel>(context);
    return Offstage(
      offstage: !gFFI.userModel.isLogin ||
          model.currentTab != PeerTabIndex.ab.index ||
          gFFI.abModel.currentAbTags.isEmpty,
      child: _hoverAction(
              context: context,
              toolTip: translate('Edit Tag'),
              onTap: () {
                editAbTagDialog(List.empty(), (selectedTags) async {
                  final peers = model.selectedPeers;
                  await gFFI.abModel.changeTagForPeers(
                      peers.map((p) => p.id).toList(), selectedTags);
                  model.setMultiSelectionMode(false);
                  showToast(translate('Successful'));
                });
              },
              child: Icon(Icons.tag))
          .marginOnly(left: !(isDesktop || isWebDesktop) ? 11 : 6),
    );
  }

  Widget selectionCount(int count) {
    return Align(
      alignment: Alignment.center,
      child: Text('$count ${translate('Selected')}'),
    );
  }

  Widget selectAll(PeerTabModel model) {
    return Offstage(
      offstage:
          model.selectedPeers.length >= model.currentTabCachedPeers.length,
      child: _hoverAction(
        context: context,
        toolTip: translate('Select All'),
        onTap: () {
          model.selectAll();
        },
        child: Icon(Icons.select_all),
      ).marginOnly(left: 6),
    );
  }

  Widget closeSelection() {
    final model = Provider.of<PeerTabModel>(context);
    return _hoverAction(
            context: context,
            toolTip: translate('Close'),
            onTap: () {
              model.setMultiSelectionMode(false);
            },
            child: Icon(Icons.clear))
        .marginOnly(left: 6);
  }

  Widget _toggleTags() {
    return _hoverAction(
        context: context,
        toolTip: translate('Toggle Tags'),
        hoverableWhenfalse: hideAbTagsPanel,
        child: Icon(
          Icons.tag_rounded,
          size: 18,
        ),
        onTap: () async {
          await bind.mainSetLocalOption(
              key: kOptionHideAbTagsPanel,
              value: hideAbTagsPanel.value ? defaultOptionNo : "Y");
          hideAbTagsPanel.value = !hideAbTagsPanel.value;
        });
  }

  List<Widget> _landscapeRightActions(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context);
    return [
      const PeerSearchBar().marginOnly(right: 13),
      _createRefresh(
          index: PeerTabIndex.ab, loading: gFFI.abModel.currentAbLoading),
      _createRefresh(
          index: PeerTabIndex.group, loading: gFFI.groupModel.groupLoading),
      Offstage(
        offstage: model.currentTabCachedPeers.isEmpty,
        child: _createMultiSelection(),
      ),
      _createPeerViewTypeSwitch(context),
      Offstage(
        offstage: model.currentTab == PeerTabIndex.recent.index,
        child: PeerSortDropdown(),
      ),
      Offstage(
        offstage: model.currentTab != PeerTabIndex.ab.index,
        child: _toggleTags(),
      ),
    ];
  }
}

class PeerSearchBar extends StatefulWidget {
  const PeerSearchBar({Key? key, this.expanded = false}) : super(key: key);

  final bool expanded;

  @override
  State<StatefulWidget> createState() => _PeerSearchBarState();
}

class _PeerSearchBarState extends State<PeerSearchBar> {
  var drawer = false;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return widget.expanded || drawer
        ? _buildSearchBar()
        : _hoverAction(
            context: context,
            toolTip: translate('Search'),
            padding: const EdgeInsets.only(right: 2),
            onTap: () {
              setState(() {
                drawer = true;
              });
            },
            child: Icon(
              Icons.search_rounded,
              color: q.muted,
            ));
  }

  Widget _buildSearchBar() {
    final q = KqTheme.of(context);
    RxBool focused = false.obs;
    FocusNode focusNode = FocusNode();
    focusNode.addListener(() {
      focused.value = focusNode.hasFocus;
    });
    return Obx(() => Container(
          height: widget.expanded ? 48 : null,
          width: widget.expanded
              ? double.infinity
              : stateGlobal.isPortrait.isTrue
                  ? 120
                  : 140,
          decoration: BoxDecoration(
            color: widget.expanded
                ? q.panelStrong.withOpacity(q.isDark ? 0.78 : 0.94)
                : q.surface,
            borderRadius: BorderRadius.circular(widget.expanded ? 16 : 12),
            border: Border.all(color: q.line.withOpacity(0.9)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: widget.expanded ? q.online : q.muted,
                    ).marginSymmetric(horizontal: widget.expanded ? 12 : 4),
                    Expanded(
                      child: TextField(
                        autofocus: !widget.expanded,
                        controller: peerSearchTextController,
                        onChanged: (searchText) {
                          peerSearchText.value = searchText;
                        },
                        focusNode: focusNode,
                        textAlign: TextAlign.start,
                        maxLines: 1,
                        cursorColor: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.color
                            ?.withOpacity(0.5),
                        cursorHeight: 18,
                        cursorWidth: 1,
                        style: TextStyle(fontSize: 14, color: q.ink),
                        decoration: InputDecoration(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          hintText:
                              focused.value || peerSearchText.value.isNotEmpty
                                  ? null
                                  : _kqPeerTabText("Search device ID or name"),
                          hintStyle: TextStyle(fontSize: 14, color: q.muted),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                    // Icon(Icons.close),
                    Obx(
                      () => Offstage(
                        offstage:
                            peerSearchText.value.isEmpty && widget.expanded,
                        child: IconButton(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 2),
                          onPressed: () {
                            setState(() {
                              peerSearchTextController.clear();
                              peerSearchText.value = "";
                              if (!widget.expanded) drawer = false;
                            });
                          },
                          icon: Tooltip(
                              message: translate('Close'),
                              child: Icon(
                                Icons.close_rounded,
                                color: q.muted,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ));
  }
}

class PeerViewDropdown extends StatefulWidget {
  const PeerViewDropdown({super.key});

  @override
  State<PeerViewDropdown> createState() => _PeerViewDropdownState();
}

class _PeerViewDropdownState extends State<PeerViewDropdown> {
  @override
  Widget build(BuildContext context) {
    final List<PeerUiType> types = [
      PeerUiType.grid,
      PeerUiType.tile,
      PeerUiType.list
    ];
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.fontSize,
        fontWeight: FontWeight.normal);
    List<PopupMenuEntry> items = List.empty(growable: true);
    items.add(PopupMenuItem(
        height: 36,
        enabled: false,
        child: Text(translate("Change view"), style: style)));
    for (var e in PeerUiType.values) {
      items.add(PopupMenuItem(
          height: 36,
          child: Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio<PeerUiType>(
                      Tooltip(
                          message: translate(types.indexOf(e) == 0
                              ? 'Big tiles'
                              : types.indexOf(e) == 1
                                  ? 'Small tiles'
                                  : 'List'),
                          child: Icon(
                            e == PeerUiType.grid
                                ? Icons.grid_view_rounded
                                : e == PeerUiType.list
                                    ? Icons.view_list_rounded
                                    : Icons.view_agenda_rounded,
                            size: 18,
                          )),
                      e,
                      peerCardUiType.value,
                      dense: true,
                      isOptionFixed(kOptionPeerCardUiType)
                          ? null
                          : (PeerUiType? v) async {
                              if (v != null) {
                                peerCardUiType.value = v;
                                setState(() {});
                                await bind.setLocalFlutterOption(
                                  k: kOptionPeerCardUiType,
                                  v: peerCardUiType.value.index.toString(),
                                );
                                if (Navigator.canPop(context)) {
                                  Navigator.pop(context);
                                }
                              }
                            }),
                ),
              ))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return _hoverAction(
        context: context,
        toolTip: translate('Change view'),
        child: Icon(
          peerCardUiType.value == PeerUiType.grid
              ? Icons.grid_view_rounded
              : peerCardUiType.value == PeerUiType.list
                  ? Icons.view_list_rounded
                  : Icons.view_agenda_rounded,
          size: 18,
        ),
        onTapDown: (details) {
          final x = details.globalPosition.dx;
          final y = details.globalPosition.dy;
          menuPos = RelativeRect.fromLTRB(x, y, x, y);
        },
        onTap: () => showMenu(
              context: context,
              position: menuPos,
              items: items,
              elevation: 8,
            ));
  }
}

class PeerSortDropdown extends StatefulWidget {
  const PeerSortDropdown({super.key});

  @override
  State<PeerSortDropdown> createState() => _PeerSortDropdownState();
}

class _PeerSortDropdownState extends State<PeerSortDropdown> {
  _PeerSortDropdownState() {
    if (!PeerSortType.values.contains(peerSort.value)) {
      _loadLocalOptions();
    }
  }

  void _loadLocalOptions() {
    peerSort.value = PeerSortType.remoteId;
    bind.setLocalFlutterOption(
      k: kOptionPeerSorting,
      v: peerSort.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        color: Theme.of(context).textTheme.titleLarge?.color,
        fontSize: MenuConfig.fontSize,
        fontWeight: FontWeight.normal);
    List<PopupMenuEntry> items = List.empty(growable: true);
    items.add(PopupMenuItem(
        height: 36,
        enabled: false,
        child: Text(translate("Sort by"), style: style)));
    for (var e in PeerSortType.values) {
      items.add(PopupMenuItem(
          height: 36,
          child: Obx(() => Center(
                child: SizedBox(
                  height: 36,
                  child: getRadio(
                      Text(translate(e), style: style), e, peerSort.value,
                      dense: true, (String? v) async {
                    if (v != null) {
                      peerSort.value = v;
                      await bind.setLocalFlutterOption(
                        k: kOptionPeerSorting,
                        v: peerSort.value,
                      );
                    }
                  }),
                ),
              ))));
    }

    var menuPos = RelativeRect.fromLTRB(0, 0, 0, 0);
    return _hoverAction(
      context: context,
      toolTip: translate('Sort by'),
      child: Icon(
        Icons.sort_rounded,
        size: 18,
      ),
      onTapDown: (details) {
        final x = details.globalPosition.dx;
        final y = details.globalPosition.dy;
        menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onTap: () => showMenu(
        context: context,
        position: menuPos,
        items: items,
        elevation: 8,
      ),
    );
  }
}

class RefreshWidget extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final RxBool? spinning;
  const RefreshWidget(
      {super.key, required this.onPressed, required this.child, this.spinning});

  @override
  State<RefreshWidget> createState() => RefreshWidgetState();
}

class RefreshWidgetState extends State<RefreshWidget> {
  double turns = 0.0;
  bool hover = false;

  @override
  void initState() {
    super.initState();
    widget.spinning?.listen((v) {
      if (v && mounted) {
        setState(() {
          turns += 1;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final deco = BoxDecoration(
      color: q.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: q.line),
    );
    return AnimatedRotation(
        turns: turns,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          if (widget.spinning?.value == true && mounted) {
            setState(() => turns += 1.0);
          }
        },
        child: Container(
          padding: EdgeInsets.all(4.0),
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration: hover ? deco : null,
          child: InkWell(
              onTap: () {
                if (mounted) setState(() => turns += 1.0);
                widget.onPressed();
              },
              onHover: (value) {
                if (mounted) {
                  setState(() {
                    hover = value;
                  });
                }
              },
              child: widget.child),
        ));
  }
}

Widget _hoverAction(
    {required BuildContext context,
    required Widget child,
    required Function() onTap,
    required String toolTip,
    GestureTapDownCallback? onTapDown,
    RxBool? hoverableWhenfalse,
    EdgeInsetsGeometry padding = const EdgeInsets.all(4.0)}) {
  final hover = false.obs;
  final q = KqTheme.of(context);
  final deco = BoxDecoration(
    color: q.surface,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: q.line),
  );
  return Tooltip(
    message: toolTip,
    child: Obx(
      () => Container(
          margin: EdgeInsets.symmetric(horizontal: 1),
          decoration:
              (hover.value || hoverableWhenfalse?.value == false) ? deco : null,
          child: InkWell(
              onHover: (value) => hover.value = value,
              onTap: onTap,
              onTapDown: onTapDown,
              child: Container(padding: padding, child: child))),
    ),
  );
}
