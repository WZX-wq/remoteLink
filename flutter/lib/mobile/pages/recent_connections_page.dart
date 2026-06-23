import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';

import '../../common.dart';
import 'page_shape.dart';

class RecentConnectionsPage extends StatelessWidget implements PageShape {
  RecentConnectionsPage({super.key});

  @override
  final title = translate('Recent devices');

  @override
  final icon = const Icon(Icons.history_rounded);

  @override
  final appBarActions = const <Widget>[];

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 18),
      child: PeerTabPage(),
    );
  }
}
