const double kMobileRemoteSideRailInset = 8;
const double kMobileRemoteSideRailItemHeight = 42;
const double kMobileRemoteSideRailItemVerticalPadding = 1;
const double kMobileRemoteSideRailContentVerticalPadding = 4;
const double kMobileRemoteToggleButtonYOffset = -72;

double mobileRemoteSideRailContentHeight({
  required int itemCount,
}) {
  return itemCount *
          (kMobileRemoteSideRailItemHeight +
              2 * kMobileRemoteSideRailItemVerticalPadding) +
      2 * kMobileRemoteSideRailContentVerticalPadding;
}
