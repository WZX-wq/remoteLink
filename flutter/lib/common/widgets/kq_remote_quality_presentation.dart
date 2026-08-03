import 'package:flutter/widgets.dart';

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
    return child;
  }
}
