import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../models/remote_video_quality_policy.dart';

class KqRemoteQualityPresentation extends StatelessWidget {
  const KqRemoteQualityPresentation({
    super.key,
    required this.streamQuality,
    required this.isStandardTier,
    required this.child,
  });

  final int streamQuality;
  final bool isStandardTier;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isStandardTier || streamQuality != kqStandardRemoteStreamQuality) {
      return child;
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: kqStandardRemoteBlurSigma,
          sigmaY: kqStandardRemoteBlurSigma,
          tileMode: TileMode.clamp,
        ),
        child: child,
      ),
    );
  }
}
