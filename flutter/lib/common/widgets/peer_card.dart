import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/kq_theme.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;
import '../../desktop/widgets/popup_menu.dart';
import 'dart:math' as math;

typedef PopupMenuEntryBuilder = Future<List<mod_menu.PopupMenuEntry<String>>>
    Function(BuildContext);

enum PeerUiType { grid, tile, list }

final peerCardUiType = PeerUiType.grid.obs;

bool? hideUsernameOnCard;

const _kqCardOnline = Color(0xFF16A77A);
const _kqCardOffline = Color(0xFFD65B68);
const _kqCardUnknown = Color(0xFF2F8FD7);
const _kqFavoriteGold = Color(0xFFFFB020);

String _kqPeerCardText(String key) {
  if (!kqUiPrefersChinese()) {
    return translate(key);
  }
  switch (key) {
    case 'Online':
      return '在线';
    case 'Offline':
      return '离线';
    case 'Checking':
      return '检测中';
    default:
      return translate(key);
  }
}

String _kqPeerStatusText(bool online) =>
    _kqPeerCardText(online ? 'Online' : 'Offline');

class _PeerCard extends StatefulWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final Function(BuildContext, String) connect;
  final PopupMenuEntryBuilder popupMenuEntryBuilder;

  const _PeerCard(
      {required this.peer,
      required this.tab,
      required this.connect,
      required this.popupMenuEntryBuilder,
      Key? key})
      : super(key: key);

  @override
  _PeerCardState createState() => _PeerCardState();
}

/// State for the connection page.
class _PeerCardState extends State<_PeerCard>
    with AutomaticKeepAliveClientMixin {
  var _menuPos = RelativeRect.fill;
  final double _cardRadius = 8;
  final double _tileRadius = 8;
  final double _borderWidth = 1;
  final RxBool _isFavorite = false.obs;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshFavoriteState();
  }

  @override
  void didUpdateWidget(covariant _PeerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.id != widget.peer.id || oldWidget.tab != widget.tab) {
      _refreshFavoriteState();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Obx(() =>
        stateGlobal.isPortrait.isTrue ? _buildPortrait() : _buildLandscape());
  }

  Widget gestureDetector({required Widget child}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final peer = super.widget.peer;
    return GestureDetector(
        onDoubleTap: peerTabModel.multiSelectionMode
            ? null
            : () => widget.connect(context, peer.id),
        onTap: () {
          if (peerTabModel.multiSelectionMode) {
            peerTabModel.select(peer);
          } else {
            if (isMobile) {
              widget.connect(context, peer.id);
            } else {
              peerTabModel.select(peer);
            }
          }
        },
        onLongPress: () => peerTabModel.select(peer),
        child: child);
  }

  Widget _buildPortrait() {
    final peer = super.widget.peer;
    return gestureDetector(child: _buildPortraitPreviewCard(context, peer));
  }

  Widget _buildPortraitPreviewCard(BuildContext context, Peer peer) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    final q = KqTheme.of(context);
    final name = hideUsernameOnCard == true
        ? peer.hostname
        : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final displayName = name.trim().isEmpty ? peer.platform : name.trim();
    final title = peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    final statusColor = peer.onlineStateKnown
        ? (peer.online ? _kqCardOnline : _kqCardOffline)
        : _kqCardUnknown;
    final colors = _frontN(peer.tags, 25)
        .map((e) => gFFI.abModel.getCurrentAbTagColor(e))
        .toList();

    Widget stopTap(Widget child) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onLongPress: () {},
        child: child,
      );
    }

    return Tooltip(
      message: '',
      child: AspectRatio(
        aspectRatio: 2.08,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? q.primary.withOpacity(0.88) : q.line,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: q.isDark
                    ? Colors.black.withOpacity(0.28)
                    : const Color(0xFF0B3C68).withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                Positioned.fill(child: _KqDesktopPreviewBackground()),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.04),
                          Colors.black.withOpacity(0.12),
                          Colors.black.withOpacity(0.72),
                        ],
                        stops: const [0.0, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
                if (colors.isNotEmpty)
                  Positioned(
                    top: 12,
                    left: 14,
                    child: CustomPaint(
                      painter: TagPainter(radius: 4, colors: colors),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: stopTap(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _favoriteButton(peer, compact: false),
                      const SizedBox(width: 4),
                      if (peerTabModel.multiSelectionMode)
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.42),
                            ),
                          ),
                          child: Icon(
                            selected
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        )
                      else
                        checkBoxOrActionMorePortrait(peer),
                    ],
                  )),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 15,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(bottom: 7),
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withOpacity(0.58),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: getPlatformImage(peer.platform, size: 21),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            if (displayName.isNotEmpty ||
                                _shouldBuildPasswordIcon(peer)) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  if (_shouldBuildPasswordIcon(peer))
                                    const Padding(
                                      padding: EdgeInsets.only(right: 5),
                                      child: Icon(
                                        Icons.key_rounded,
                                        color: Colors.white70,
                                        size: 13,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      peer.onlineStateKnown
                                          ? _kqPeerStatusText(peer.online)
                                          : _kqPeerCardText('Checking'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLandscape() {
    final peer = super.widget.peer;
    final q = KqTheme.of(context);
    final isReferenceRecentCard = widget.tab == PeerTabIndex.recent;
    var deco = Rx<BoxDecoration?>(
      BoxDecoration(
        border: Border.all(color: Colors.transparent, width: _borderWidth),
        borderRadius: BorderRadius.circular(
          peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
        ),
      ),
    );
    return MouseRegion(
      onEnter: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(
              color: q.primary.withOpacity(0.72), width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      onExit: (evt) {
        deco.value = BoxDecoration(
          border: Border.all(color: Colors.transparent, width: _borderWidth),
          borderRadius: BorderRadius.circular(
            peerCardUiType.value == PeerUiType.grid ? _cardRadius : _tileRadius,
          ),
        );
      },
      child: gestureDetector(
          child: Obx(() => peerCardUiType.value == PeerUiType.grid
              ? isReferenceRecentCard
                  ? _buildKqReferenceRecentCard(context, peer, deco)
                  : _buildPeerCard(context, peer, deco)
              : _buildPeerTile(context, peer, deco))),
    );
  }

  bool _showNote(Peer peer) {
    return peerTabShowNote(widget.tab) && peer.note.isNotEmpty;
  }

  makeChild(bool isPortrait, Peer peer) {
    final name = hideUsernameOnCard == true
        ? peer.hostname
        : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final displayName = name.trim().isEmpty ? peer.platform : name.trim();
    final title = peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    final q = KqTheme.of(context);
    final greyStyle = TextStyle(
      fontSize: 11,
      color: q.muted,
      height: 1.05,
    );
    final showNote = _showNote(peer);

    return Container(
      decoration: BoxDecoration(
        color: q.surface,
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(color: q.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            alignment: Alignment.center,
            width: isPortrait ? 52 : 42,
            height: isPortrait ? 52 : 40,
            margin: EdgeInsets.only(left: isPortrait ? 8 : 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [q.iconTile, q.iconTile2],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: q.iconBorder),
            ),
            child: Stack(
              children: [
                Center(
                  child: getPlatformImage(peer.platform,
                      size: isPortrait ? 34 : 27),
                ),
                if (_shouldBuildPasswordIcon(peer))
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Icon(Icons.key_rounded, size: 8, color: q.primary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  getOnline(7, peer.online, known: peer.onlineStateKnown),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Tooltip(
                        message: displayName,
                        waitDuration: const Duration(seconds: 1),
                        child: Text(
                          displayName,
                          style: greyStyle,
                          textAlign: TextAlign.start,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (showNote)
                      Expanded(
                        child: Tooltip(
                          message: peer.note,
                          waitDuration: const Duration(seconds: 1),
                          child: Text(
                            peer.note,
                            style: greyStyle,
                            textAlign: TextAlign.start,
                            overflow: TextOverflow.ellipsis,
                          ).marginOnly(
                              left: peerCardUiType.value == PeerUiType.list
                                  ? 22
                                  : 6),
                        ),
                      )
                  ],
                ),
              ],
            ),
          ),
          isPortrait
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _favoriteButton(peer, compact: false),
                    checkBoxOrActionMorePortrait(peer),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _favoriteButton(peer, compact: true),
                    checkBoxOrActionMoreLandscape(peer, isTile: true),
                  ],
                ),
        ],
      ).paddingOnly(right: 4),
    );
  }

  Widget _buildPeerTile(
      BuildContext context, Peer peer, Rx<BoxDecoration?>? deco) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final colors = _frontN(peer.tags, 25)
        .map((e) => gFFI.abModel.getCurrentAbTagColor(e))
        .toList();
    return Tooltip(
      message: !(isDesktop || isWebDesktop)
          ? ''
          : peer.tags.isNotEmpty
              ? '${translate('Tags')}: ${peer.tags.join(', ')}'
              : '',
      child: Stack(children: [
        Obx(
          () => deco == null
              ? makeChild(stateGlobal.isPortrait.isTrue, peer)
              : Container(
                  foregroundDecoration: deco.value,
                  child: makeChild(stateGlobal.isPortrait.isTrue, peer),
                ),
        ),
        if (colors.isNotEmpty)
          Obx(() => Positioned(
                top: 2,
                right: stateGlobal.isPortrait.isTrue ? 20 : 10,
                child: CustomPaint(
                  painter: TagPainter(radius: 3, colors: colors),
                ),
              ))
      ]),
    );
  }

  Widget _buildPeerCard(
      BuildContext context, Peer peer, Rx<BoxDecoration?> deco) {
    hideUsernameOnCard ??=
        bind.mainGetBuildinOption(key: kHideUsernameOnCard) == 'Y';
    final name = hideUsernameOnCard == true
        ? peer.hostname
        : '${peer.username}${peer.username.isNotEmpty && peer.hostname.isNotEmpty ? '@' : ''}${peer.hostname}';
    final displayName = name.trim().isEmpty ? peer.platform : name.trim();
    final title = peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    final q = KqTheme.of(context);
    final child = Obx(
      () => Container(
        foregroundDecoration: deco.value,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: q.surface,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: q.line),
          boxShadow: [
            BoxShadow(
              color: q.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [q.iconTile, q.iconTile2],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: q.iconBorder),
              ),
              child: Stack(
                children: [
                  Center(child: getPlatformImage(peer.platform, size: 29)),
                  if (_shouldBuildPasswordIcon(peer))
                    Positioned(
                      top: 3,
                      left: 3,
                      child: Icon(Icons.key_rounded, size: 9, color: q.primary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Tooltip(
                    message: displayName,
                    waitDuration: const Duration(seconds: 1),
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: q.muted,
                        fontSize: 12,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (_showNote(peer)) ...[
                    const SizedBox(height: 3),
                    Tooltip(
                      message: peer.note,
                      waitDuration: const Duration(seconds: 1),
                      child: Text(
                        peer.note,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: q.muted.withOpacity(0.78),
                          fontSize: 11,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusPill(online: peer.online, known: peer.onlineStateKnown),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _favoriteButton(peer, compact: true),
                    checkBoxOrActionMoreLandscape(peer, isTile: false),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final colors = _frontN(peer.tags, 25)
        .map((e) => gFFI.abModel.getCurrentAbTagColor(e))
        .toList();
    return Tooltip(
      message: peer.tags.isNotEmpty
          ? '${translate('Tags')}: ${peer.tags.join(', ')}'
          : '',
      child: Stack(children: [
        child,
        if (colors.isNotEmpty)
          Positioned(
            top: 4,
            right: 12,
            child: CustomPaint(
              painter: TagPainter(radius: 4, colors: colors),
            ),
          )
      ]),
    );
  }

  Widget _buildKqReferenceRecentCard(
      BuildContext context, Peer peer, Rx<BoxDecoration?> deco) {
    final title = peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    final rawSubtitle =
        peer.hostname.trim().isNotEmpty ? peer.hostname : peer.username;
    final subtitle = rawSubtitle.trim().isEmpty ? '远程设备' : rawSubtitle.trim();
    const cardRadius = 8.0;
    final q = KqTheme.of(context);
    final peerTabModel = Provider.of<PeerTabModel>(context);
    return Obx(() {
      final selected = peerTabModel.isPeerSelected(peer.id);
      final statusColor = peer.onlineStateKnown
          ? (peer.online ? _kqCardOnline : _kqCardOffline)
          : _kqCardUnknown;
      final statusText = peer.onlineStateKnown
          ? _kqPeerStatusText(peer.online)
          : _kqPeerCardText('Checking');
      return Tooltip(
        message: title,
        waitDuration: const Duration(seconds: 1),
        child: Listener(
          onPointerDown: (e) {
            if (e.buttons == 2) {
              final x = e.position.dx;
              final y = e.position.dy;
              _menuPos = RelativeRect.fromLTRB(x, y, x, y);
              _showPeerMenu(peer.id);
            }
          },
          child: Container(
            // kq-recent-reference-card
            // kq-recent-reference-card-light-blue
            // kq-v213-recent-white-card
            foregroundDecoration: selected
                ? BoxDecoration(
                    border: Border.all(
                      color: q.primary.withOpacity(0.78),
                      width: 1.6,
                    ),
                    borderRadius: BorderRadius.circular(cardRadius),
                  )
                : deco.value,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cardRadius),
              color: q.isDark ? q.panelStrong.withOpacity(0.9) : Colors.white,
              border: Border.all(
                color: q.isDark
                    ? q.line.withOpacity(0.84)
                    : const Color(0xFFE5EAF0),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1D4ED8)
                      .withOpacity(q.isDark ? 0.10 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        // kq-recent-card-platform-watermark-visible
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: q.primary.withOpacity(q.isDark ? 0.16 : 0.10),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: ColorFiltered(
                              // kq-recent-card-platform-icon-visible-color
                              colorFilter: ColorFilter.mode(
                                q.primaryDeep
                                    .withOpacity(q.isDark ? 0.86 : 0.78),
                                BlendMode.srcIn,
                              ),
                              child: getPlatformImage(peer.platform, size: 22),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggleFavorite(peer.id),
                        child: Obx(() {
                          final isFavorite = _isFavorite.value;
                          return SizedBox(
                            width: 30,
                            height: 30,
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 20,
                              color: isFavorite
                                  ? const Color(0xFFF43F5E)
                                  : const Color(0xFF9AA7B8),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: q.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: q.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.05,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  List _frontN<T>(List list, int n) {
    if (list.length <= n) {
      return list;
    } else {
      return list.sublist(0, n);
    }
  }

  Widget checkBoxOrActionMorePortrait(Peer peer) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: selected
            ? Icon(
                Icons.check_box,
                color: MyTheme.accent,
              )
            : Icon(Icons.check_box_outline_blank),
      );
    } else {
      return InkWell(
          borderRadius: BorderRadius.circular(999),
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.more_vert_rounded,
                color: stateGlobal.isPortrait.isTrue
                    ? Colors.white
                    : KqTheme.of(context).muted,
              )),
          onTapDown: (e) {
            final x = e.globalPosition.dx;
            final y = e.globalPosition.dy;
            _menuPos = RelativeRect.fromLTRB(x, y, x, y);
          },
          onTap: () {
            _showPeerMenu(peer.id);
          });
    }
  }

  Widget checkBoxOrActionMoreLandscape(Peer peer, {required bool isTile}) {
    final PeerTabModel peerTabModel = Provider.of(context);
    final selected = peerTabModel.isPeerSelected(peer.id);
    if (peerTabModel.multiSelectionMode) {
      final icon = selected
          ? Icon(
              Icons.check_box,
              color: MyTheme.accent,
            )
          : Icon(Icons.check_box_outline_blank);
      bool last = peerTabModel.isShiftDown && peer.id == peerTabModel.lastId;
      double right = isTile ? 4 : 0;
      if (last) {
        return Container(
          decoration: BoxDecoration(
              border: Border.all(color: MyTheme.accent, width: 1)),
          child: icon,
        ).marginOnly(right: right);
      } else {
        return icon.marginOnly(right: right);
      }
    } else {
      return _actionMore(peer);
    }
  }

  Widget _actionMore(Peer peer) => Listener(
      onPointerDown: (e) {
        final x = e.position.dx;
        final y = e.position.dy;
        _menuPos = RelativeRect.fromLTRB(x, y, x, y);
      },
      onPointerUp: (_) => _showPeerMenu(peer.id),
      child: build_more(context));

  Future<void> _refreshFavoriteState() async {
    final favs = (await bind.mainGetFav()).map((id) => id.toString()).toSet();
    if (!mounted) return;
    _isFavorite.value =
        widget.tab == PeerTabIndex.fav || favs.contains(widget.peer.id);
  }

  Widget _favoriteButton(Peer peer, {required bool compact}) {
    final q = KqTheme.of(context);
    final size = compact ? 26.0 : 30.0;
    return Obx(() {
      final isFavorite = _isFavorite.value;
      return Tooltip(
        message: translate(
            isFavorite ? 'Remove from Favorites' : 'Add to Favorites'),
        waitDuration: const Duration(milliseconds: 500),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _toggleFavorite(peer.id),
          child: Container(
            width: size,
            height: size,
            margin: EdgeInsets.only(right: compact ? 2 : 0),
            decoration: BoxDecoration(
              color: isFavorite
                  ? _kqFavoriteGold.withOpacity(0.16)
                  : q.surfaceSoft.withOpacity(0.72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isFavorite
                    ? _kqFavoriteGold.withOpacity(0.72)
                    : q.line.withOpacity(0.9),
              ),
            ),
            child: Icon(
              isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              size: compact ? 16 : 18,
              color: isFavorite ? _kqFavoriteGold : q.muted.withOpacity(0.82),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _toggleFavorite(String id) async {
    if (_favoriteBusy) return;
    _favoriteBusy = true;
    try {
      final favs =
          (await bind.mainGetFav()).map((id) => id.toString()).toList();
      final wasFavorite = favs.contains(id);
      if (wasFavorite) {
        favs.remove(id);
      } else {
        favs.add(id);
      }
      await bind.mainStoreFav(favs: favs);
      if (mounted) {
        _isFavorite.value = !wasFavorite;
      }
      bind.mainLoadFavPeers();
      bind.mainLoadRecentPeers();
      showToast(translate('Successful'));
    } finally {
      _favoriteBusy = false;
    }
  }

  bool _shouldBuildPasswordIcon(Peer peer) {
    if (gFFI.peerTabModel.currentTab != PeerTabIndex.ab.index) return false;
    if (gFFI.abModel.current.isPersonal()) return false;
    return peer.password.isNotEmpty;
  }

  /// Show the peer menu and handle user's choice.
  /// User might remove the peer or send a file to the peer.
  void _showPeerMenu(String id) async {
    await mod_menu.showMenu(
      context: context,
      position: _menuPos,
      items: await super.widget.popupMenuEntryBuilder(context),
      elevation: 8,
    );
  }

  @override
  bool get wantKeepAlive => true;
}

abstract class BasePeerCard extends StatelessWidget {
  final Peer peer;
  final PeerTabIndex tab;
  final EdgeInsets? menuPadding;

  BasePeerCard(
      {required this.peer, required this.tab, this.menuPadding, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _PeerCard(
      peer: peer,
      tab: tab,
      connect: (BuildContext context, String id) =>
          connectInPeerTab(context, peer, tab),
      popupMenuEntryBuilder: _buildPopupMenuEntry,
    );
  }

  Future<List<mod_menu.PopupMenuEntry<String>>> _buildPopupMenuEntry(
          BuildContext context) async =>
      (await _buildMenuItems(context))
          .map((e) => e.build(
              context,
              const MenuConfig(
                  commonColor: CustomPopupMenuTheme.commonColor,
                  height: CustomPopupMenuTheme.height,
                  dividerHeight: CustomPopupMenuTheme.dividerHeight)))
          .expand((i) => i)
          .toList();

  @protected
  Future<List<MenuEntryBase<String>>> _buildMenuItems(BuildContext context);

  MenuEntryBase<String> _connectCommonAction(
    BuildContext context,
    String title, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
    bool isTerminal = false,
    bool isTerminalRunAsAdmin = false,
  }) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        title,
        style: style,
      ),
      proc: () {
        if (isTerminalRunAsAdmin) {
          setEnvTerminalAdmin();
        }
        connectInPeerTab(
          context,
          peer,
          tab,
          isFileTransfer: isFileTransfer,
          isViewCamera: isViewCamera,
          isTcpTunneling: isTcpTunneling,
          isRDP: isRDP,
          isTerminal: isTerminal || isTerminalRunAsAdmin,
        );
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _connectAction(BuildContext context) {
    return _connectCommonAction(
      context,
      (peer.alias.isEmpty
          ? translate('Connect')
          : '${translate('Connect')} ${peer.id}'),
    );
  }

  @protected
  MenuEntryBase<String> _transferFileAction(BuildContext context) {
    return _connectCommonAction(
      context,
      translate('Transfer file'),
      isFileTransfer: true,
    );
  }

  List<MenuEntryBase<String>> _viewCameraActions(BuildContext context) {
    if (!kShowViewCameraConnectAction) {
      return [];
    }
    return [];
  }

  @protected
  MenuEntryBase<String> _wolAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('WOL'),
        style: style,
      ),
      proc: () {
        bind.mainWol(id: id);
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  /// Only available on Windows.
  @protected
  MenuEntryBase<String> _createShortCutAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Create desktop shortcut'),
        style: style,
      ),
      proc: () {
        bind.mainCreateShortcut(id: id);
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  Future<MenuEntryBase<String>> _openNewConnInAction(
      String id, String label, String key) async {
    return MenuEntrySwitch<String>(
      switchType: SwitchType.scheckbox,
      text: translate(label),
      getter: () async => mainGetPeerBoolOptionSync(id, key),
      setter: (bool v) async {
        await bind.mainSetPeerOption(
            id: id, key: key, value: bool2option(key, v));
        showToast(translate('Successful'));
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  _openInTabsAction(String id) async =>
      await _openNewConnInAction(id, 'Open in New Tab', kOptionOpenInTabs);

  _openInWindowsAction(String id) async => await _openNewConnInAction(
      id, 'Open in new window', kOptionOpenInWindows);

  // ignore: unused_element
  _openNewConnInOptAction(String id) async =>
      mainGetLocalBoolOptionSync(kOptionOpenNewConnInTabs)
          ? await _openInWindowsAction(id)
          : await _openInTabsAction(id);

  @protected
  MenuEntryBase<String> _renameAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Rename'),
        style: style,
      ),
      proc: () async {
        String oldName = await _getAlias(id);
        renameDialog(
            oldName: oldName,
            onSubmit: (String newName) async {
              if (newName != oldName) {
                if (tab == PeerTabIndex.ab) {
                  await gFFI.abModel.changeAlias(id: id, alias: newName);
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                } else {
                  await bind.mainSetPeerAlias(id: id, alias: newName);
                  showToast(translate('Successful'));
                  _update();
                }
              }
            });
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _removeAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Delete'),
            style: style?.copyWith(color: Colors.red),
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.delete_forever, color: Colors.red),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        onSubmit() async {
          switch (tab) {
            case PeerTabIndex.recent:
              await deleteKqRecentPeer(id);
              bind.mainLoadRecentPeers();
              break;
            case PeerTabIndex.fav:
              final favs = (await bind.mainGetFav()).toList();
              if (favs.remove(id)) {
                await bind.mainStoreFav(favs: favs);
                bind.mainLoadFavPeers();
              }
              break;
            case PeerTabIndex.lan:
              await bind.mainRemoveDiscovered(id: id);
              bind.mainLoadLanPeers();
              break;
            case PeerTabIndex.ab:
              await gFFI.abModel.deletePeers([id]);
              break;
            case PeerTabIndex.group:
              break;
          }
          if (tab != PeerTabIndex.ab) {
            showToast(translate('Successful'));
          }
        }

        deleteConfirmDialog(onSubmit,
            '${translate('Delete')} "${peer.alias.isEmpty ? formatID(peer.id) : peer.alias}"?');
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _unrememberPasswordAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Forget Password'),
        style: style,
      ),
      proc: () async {
        bool succ = await gFFI.abModel.changePersonalHashPassword(id, '');
        await bind.mainForgetPassword(id: id);
        if (succ) {
          showToast(translate('Successful'));
        } else {
          if (tab.index == PeerTabIndex.ab.index) {
            BotToast.showText(
                contentColor: Colors.red, text: translate("Failed"));
          }
        }
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addFavAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Add to Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star_outline),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (!favs.contains(id)) {
            favs.add(id);
            await bind.mainStoreFav(favs: favs);
          }
          bind.mainLoadFavPeers();
          bind.mainLoadRecentPeers();
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _rmFavAction(
      String id, Future<void> Function() reloadFunc) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Row(
        children: [
          Text(
            translate('Remove from Favorites'),
            style: style,
          ),
          Expanded(
              child: Align(
            alignment: Alignment.centerRight,
            child: Transform.scale(
              scale: 0.8,
              child: Icon(Icons.star),
            ),
          ).marginOnly(right: 4)),
        ],
      ),
      proc: () {
        () async {
          final favs = (await bind.mainGetFav()).toList();
          if (favs.remove(id)) {
            await bind.mainStoreFav(favs: favs);
            await reloadFunc();
          }
          bind.mainLoadFavPeers();
          bind.mainLoadRecentPeers();
          showToast(translate('Successful'));
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _addToAb(Peer peer) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Add to address book'),
        style: style,
      ),
      proc: () {
        () async {
          addPeersToAbDialog([Peer.copy(peer)]);
        }();
      },
      padding: menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  Future<String> _getAlias(String id) async =>
      await bind.mainGetPeerOption(id: id, key: 'alias');

  @protected
  void _update();
}

class RecentPeerCard extends BasePeerCard {
  RecentPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.recent,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      ..._viewCameraActions(context),
    ];

    final List favs = (await bind.mainGetFav()).toList();

    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadRecentPeers();
}

class FavoritePeerCard extends BasePeerCard {
  FavoritePeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.fav,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      ..._viewCameraActions(context),
    ];

    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    menuItems.add(MenuEntryDivider());
    if (isMobile || isDesktop || isWebDesktop) {
      menuItems.add(_renameAction(peer.id));
    }
    if (await bind.mainPeerHasPassword(id: peer.id)) {
      menuItems.add(_unrememberPasswordAction(peer.id));
    }
    menuItems.add(_rmFavAction(peer.id, () async {
      await bind.mainLoadFavPeers();
    }));

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadFavPeers();
}

class DiscoveredPeerCard extends BasePeerCard {
  DiscoveredPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.lan,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      ..._viewCameraActions(context),
    ];

    final List favs = (await bind.mainGetFav()).toList();

    menuItems.add(_wolAction(peer.id));
    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }

    if (!favs.contains(peer.id)) {
      menuItems.add(_addFavAction(peer.id));
    } else {
      menuItems.add(_rmFavAction(peer.id, () async {}));
    }

    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }

    menuItems.add(MenuEntryDivider());
    menuItems.add(_removeAction(peer.id));
    return menuItems;
  }

  @protected
  @override
  void _update() => bind.mainLoadLanPeers();
}

class AddressBookPeerCard extends BasePeerCard {
  AddressBookPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.ab,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      ..._viewCameraActions(context),
    ];

    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    if (gFFI.abModel.current.canWrite()) {
      menuItems.add(MenuEntryDivider());
      if (isMobile || isDesktop || isWebDesktop) {
        menuItems.add(_renameAction(peer.id));
      }
      if (gFFI.abModel.current.isPersonal() && peer.hash.isNotEmpty) {
        menuItems.add(_unrememberPasswordAction(peer.id));
      }
      if (!gFFI.abModel.current.isPersonal()) {
        menuItems.add(_changeSharedAbPassword());
      }
      if (gFFI.abModel.currentAbTags.isNotEmpty) {
        menuItems.add(_editTagAction(peer.id));
      }
      menuItems.add(_editNoteAction(peer.id));
    }
    final addressbooks = gFFI.abModel.addressBooksCanWrite();
    if (gFFI.peerTabModel.currentTab == PeerTabIndex.ab.index) {
      addressbooks.remove(gFFI.abModel.currentName.value);
    }
    if (addressbooks.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }
    menuItems.add(_existIn());
    if (gFFI.abModel.current.canWrite()) {
      menuItems.add(MenuEntryDivider());
      menuItems.add(_removeAction(peer.id));
    }
    return menuItems;
  }

  // address book does not need to update
  @protected
  @override
  void _update() =>
      {}; //gFFI.abModel.pullAb(force: ForcePullAb.current, quiet: true);

  @protected
  MenuEntryBase<String> _editTagAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Edit Tag'),
        style: style,
      ),
      proc: () {
        editAbTagDialog(gFFI.abModel.getPeerTags(id), (selectedTag) async {
          await gFFI.abModel.changeTagForPeers([id], selectedTag);
        });
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  MenuEntryBase<String> _editNoteAction(String id) {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Edit note'),
        style: style,
      ),
      proc: () {
        editAbPeerNoteDialog(id);
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  @protected
  @override
  Future<String> _getAlias(String id) async =>
      gFFI.abModel.find(id)?.alias ?? '';

  MenuEntryBase<String> _changeSharedAbPassword() {
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate(
            peer.password.isEmpty ? 'Set shared password' : 'Change Password'),
        style: style,
      ),
      proc: () {
        setSharedAbPasswordDialog(gFFI.abModel.currentName.value, peer);
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }

  MenuEntryBase<String> _existIn() {
    final names = gFFI.abModel.idExistIn(peer.id);
    final text = names.join(', ');
    return MenuEntryButton<String>(
      childBuilder: (TextStyle? style) => Text(
        translate('Exist in'),
        style: style,
      ),
      proc: () {
        gFFI.dialogManager.show((setState, close, context) {
          return CustomAlertDialog(
            title: Text(translate('Exist in')),
            content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(text)]),
            actions: [
              dialogButton(
                "OK",
                icon: Icon(Icons.done_rounded),
                onPressed: close,
              ),
            ],
            onSubmit: close,
            onCancel: close,
          );
        });
      },
      padding: super.menuPadding,
      dismissOnClicked: true,
    );
  }
}

class MyGroupPeerCard extends BasePeerCard {
  MyGroupPeerCard({required Peer peer, EdgeInsets? menuPadding, Key? key})
      : super(
            peer: peer,
            tab: PeerTabIndex.group,
            menuPadding: menuPadding,
            key: key);

  @override
  Future<List<MenuEntryBase<String>>> _buildMenuItems(
      BuildContext context) async {
    final List<MenuEntryBase<String>> menuItems = [
      _connectAction(context),
      _transferFileAction(context),
      ..._viewCameraActions(context),
    ];

    if (isWindows) {
      menuItems.add(_createShortCutAction(peer.id));
    }
    // menuItems.add(MenuEntryDivider());
    // menuItems.add(_renameAction(peer.id));
    // if (await bind.mainPeerHasPassword(id: peer.id)) {
    //   menuItems.add(_unrememberPasswordAction(peer.id));
    // }
    if (gFFI.userModel.userName.isNotEmpty) {
      menuItems.add(_addToAb(peer));
    }
    return menuItems;
  }

  @protected
  @override
  void _update() => gFFI.groupModel.pull();
}

class _StatusPill extends StatelessWidget {
  final bool online;
  final bool known;

  const _StatusPill({required this.online, required this.known});

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final color = known ? (online ? q.online : q.offline) : q.primary;
    final text =
        known ? _kqPeerStatusText(online) : _kqPeerCardText('Checking');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _KqDesktopPreviewBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KqDesktopPreviewPainter(KqTheme.of(context).isDark),
    );
  }
}

class _KqDesktopPreviewPainter extends CustomPainter {
  const _KqDesktopPreviewPainter(this.isDark);

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [
                Color(0xFF061426),
                Color(0xFF0A3150),
                Color(0xFF07101F),
              ]
            : const [
                Color(0xFF082548),
                Color(0xFF0B5A85),
                Color(0xFF061B35),
              ],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.62, -0.15),
        radius: 0.95,
        colors: [
          const Color(0xFF37D3C5).withOpacity(0.52),
          const Color(0xFF1277D9).withOpacity(0.20),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      canvas.drawLine(
          Offset(x, 0), Offset(x - size.width * 0.12, size.height), linePaint);
    }

    final panePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF4FE0D0).withOpacity(0.52),
          const Color(0xFF1E8CFF).withOpacity(0.20),
        ],
      ).createShader(rect);
    final darkPanePaint = Paint()..color = const Color(0xFF031126);

    final leftTop = Path()
      ..moveTo(size.width * 0.13, size.height * 0.20)
      ..lineTo(size.width * 0.52, size.height * 0.12)
      ..lineTo(size.width * 0.51, size.height * 0.48)
      ..lineTo(size.width * 0.10, size.height * 0.50)
      ..close();
    final rightTop = Path()
      ..moveTo(size.width * 0.56, size.height * 0.12)
      ..lineTo(size.width * 0.86, size.height * 0.22)
      ..lineTo(size.width * 0.86, size.height * 0.48)
      ..lineTo(size.width * 0.55, size.height * 0.48)
      ..close();
    final leftBottom = Path()
      ..moveTo(size.width * 0.10, size.height * 0.54)
      ..lineTo(size.width * 0.51, size.height * 0.52)
      ..lineTo(size.width * 0.51, size.height * 0.86)
      ..lineTo(size.width * 0.15, size.height * 0.72)
      ..close();
    final rightBottom = Path()
      ..moveTo(size.width * 0.55, size.height * 0.52)
      ..lineTo(size.width * 0.86, size.height * 0.52)
      ..lineTo(size.width * 0.84, size.height * 0.78)
      ..lineTo(size.width * 0.56, size.height * 0.86)
      ..close();

    canvas.drawPath(leftTop, panePaint);
    canvas.drawPath(rightTop, panePaint);
    canvas.drawPath(leftBottom, panePaint);
    canvas.drawPath(rightBottom, panePaint);

    final separatorPaint = Paint()
      ..color = darkPanePaint.color.withOpacity(0.82)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(size.width * 0.535, size.height * 0.12),
      Offset(size.width * 0.535, size.height * 0.88),
      separatorPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.51),
      Offset(size.width * 0.87, size.height * 0.50),
      separatorPaint,
    );

    final sheenPaint = Paint()
      ..color = Colors.white.withOpacity(0.09)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.25),
      Offset(size.width * 0.50, size.height * 0.18),
      sheenPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.20),
      Offset(size.width * 0.82, size.height * 0.28),
      sheenPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KqDesktopPreviewPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}

Widget getOnline(double rightPadding, bool online, {bool known = true}) {
  final color =
      known ? (online ? _kqCardOnline : _kqCardOffline) : _kqCardUnknown;
  final text = known ? _kqPeerStatusText(online) : _kqPeerCardText('Checking');
  return Tooltip(
      message: text,
      waitDuration: const Duration(seconds: 1),
      child: Padding(
          padding: EdgeInsets.fromLTRB(0, 4, rightPadding, 4),
          child: CircleAvatar(radius: 3, backgroundColor: color)));
}

Widget build_more(BuildContext context, {bool invert = false}) {
  final RxBool hover = false.obs;
  final q = KqTheme.of(context);
  return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {},
      onHover: (value) => hover.value = value,
      child: Obx(() => CircleAvatar(
          radius: 14,
          backgroundColor: hover.value
              ? q.surfaceSoft
              : (invert ? q.surface : q.panelStrong.withOpacity(0.72)),
          child: Icon(Icons.more_vert,
              size: 18, color: hover.value ? q.primary : q.muted))));
}

class TagPainter extends CustomPainter {
  final double radius;
  late final List<Color> colors;

  TagPainter({required this.radius, required List<Color> colors}) {
    this.colors = colors.reversed.toList();
  }

  @override
  void paint(Canvas canvas, Size size) {
    double x = 0;
    double y = radius;
    for (int i = 0; i < colors.length; i++) {
      Paint paint = Paint();
      paint.color = colors[i];
      x -= radius + 1;
      if (i == colors.length - 1) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      } else {
        Path path = Path();
        path.addArc(Rect.fromCircle(center: Offset(x, y), radius: radius),
            math.pi * 4 / 3, math.pi * 4 / 3);
        path.addArc(
            Rect.fromCircle(center: Offset(x - radius, y), radius: radius),
            math.pi * 5 / 3,
            math.pi * 2 / 3);
        path.fillType = PathFillType.evenOdd;
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

void connectInPeerTab(BuildContext context, Peer peer, PeerTabIndex tab,
    {bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTcpTunneling = false,
    bool isRDP = false,
    bool isTerminal = false}) async {
  var password = '';
  bool isSharedPassword = false;
  if (tab == PeerTabIndex.ab) {
    // If recent peer's alias is empty, set it to ab's alias
    // Because the platform is not set, it may not take effect, but it is more important not to display if the connection is not successful
    if (peer.alias.isNotEmpty &&
        (await bind.mainGetPeerOption(id: peer.id, key: "alias")).isEmpty) {
      await bind.mainSetPeerAlias(
        id: peer.id,
        alias: peer.alias,
      );
    }
    if (!gFFI.abModel.current.isPersonal()) {
      if (peer.password.isNotEmpty) {
        password = peer.password;
        isSharedPassword = true;
      }
      if (password.isEmpty) {
        final abPassword = gFFI.abModel.getdefaultSharedPassword();
        if (abPassword != null) {
          password = abPassword;
          isSharedPassword = true;
        }
      }
    }
  }
  connect(context, peer.id,
      password: password,
      isSharedPassword: isSharedPassword,
      isFileTransfer: isFileTransfer,
      isTerminal: isTerminal,
      isViewCamera: isViewCamera,
      isTcpTunneling: isTcpTunneling,
      isRDP: isRDP);
}
