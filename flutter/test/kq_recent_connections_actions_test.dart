import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('mobile recent connection actions use a compact bottom sheet', () {
    final peerCard = _read('lib/common/widgets/peer_card.dart');

    expect(peerCard, contains('mobileActionSheetBuilder'));
    expect(
      peerCard,
      contains(
          'tab == PeerTabIndex.recent ? _showMobilePeerActionSheet : null'),
    );
    expect(peerCard, contains('if (isMobile &&'));
    expect(peerCard, contains('stateGlobal.isPortrait.isTrue'));
    expect(peerCard, contains('widget.mobileActionSheetBuilder != null'));
    expect(peerCard, contains('showModalBottomSheet'));
    expect(peerCard, contains('_MobilePeerActionTile'));

    final recentMenu = _section(
      peerCard,
      'Future<void> _showMobilePeerActionSheet',
      'MenuEntryBase<String> _connectCommonAction',
    );
    expect(recentMenu, contains("label: translate('Connect')"));
    expect(recentMenu, contains("label: translate('Transfer file')"));
    expect(recentMenu, contains("label: translate('Rename')"));
    expect(recentMenu, contains("label: translate('Delete')"));
    expect(recentMenu, isNot(contains("label: favoriteLabel")));
    expect(recentMenu, isNot(contains("Icons.contacts_rounded")));
    expect(recentMenu, isNot(contains("Add to address book")));
  });

  test('deleting recent account devices hides them before the next reload', () {
    final peerCard = _read('lib/common/widgets/peer_card.dart');
    final peerTab = _read('lib/common/widgets/peer_tab_page.dart');
    final peerModel = _read('lib/models/peer_model.dart');
    final peersView = _read('lib/common/widgets/peers_view.dart');
    final api = _read('lib/common/kq_project_api.dart');

    expect(peerModel, contains('bool removePeerById('));
    expect(peerCard, contains('KqProjectApi.markAccountDeviceHidden(peer);'));
    expect(
      peerCard,
      contains(
          'gFFI.recentPeersModel.removePeerById(id, notifyIfMissing: true);'),
    );
    expect(peerTab,
        contains('final peers = List<Peer>.from(model.selectedPeers);'));
    expect(peerTab, contains('KqProjectApi.markAccountDeviceHidden(p);'));
    expect(
      peerTab,
      contains(
          'gFFI.recentPeersModel.removePeerById(\n                    p.id,'),
    );
    expect(api, contains('filterHiddenAccountDevices'));
    expect(
      peersView,
      contains('KqProjectApi.filterHiddenAccountDevices(_accountDevicePeers)'),
    );
  });
}
