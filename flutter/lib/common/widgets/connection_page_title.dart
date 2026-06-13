import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:get/get.dart';

import '../../common.dart';

Widget getConnectionPageTitle(BuildContext context, bool isWeb) {
  final q = KqTheme.of(context);
  return Row(
    children: [
      Expanded(
          child: Row(
        children: [
          AutoSizeText(
            translate('Control Remote Desktop'),
            maxLines: 1,
            minFontSize: 15,
            style: TextStyle(
              color: q.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: 0,
            ),
          ).marginOnly(right: 4),
          Tooltip(
            waitDuration: Duration(milliseconds: 300),
            message: translate(isWeb ? "web_id_input_tip" : "id_input_tip"),
            child: Icon(
              Icons.help_outline_outlined,
              size: 16,
              color: q.muted.withOpacity(0.72),
            ),
          ),
        ],
      )),
    ],
  );
}
