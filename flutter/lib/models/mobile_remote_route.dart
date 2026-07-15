import 'package:flutter/material.dart';

bool removeRegisteredMobileRemoteRoute({
  required NavigatorState navigator,
  required Route<dynamic>? route,
}) {
  if (route == null ||
      !route.isActive ||
      !identical(route.navigator, navigator)) {
    return false;
  }
  navigator.removeRoute(route);
  return true;
}
