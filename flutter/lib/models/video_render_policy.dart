bool shouldUseNativeVideoTexture({
  required bool isDesktopPlatform,
  required bool nativeTextureAvailable,
}) {
  return isDesktopPlatform && nativeTextureAvailable;
}

bool shouldBuildRemoteToolbarPerformanceMenu({
  required bool isWindowsPlatform,
}) {
  // Material MenuBar/SubmenuButton creates a separate overlay layer. On the
  // Windows remote scene, revealing this menu bar can replace the complete
  // RemotePage with a 244 px white menu surface and a gray modal barrier.
  // Quality selection remains available in account settings.
  return !isWindowsPlatform;
}

bool shouldShowRemoteConnectionOverlay({
  required bool isWindowsPlatform,
  required bool isDesktopPlatform,
  required bool isWebPlatform,
}) {
  // The desktop remote page runs in a separate Flutter engine on Windows.
  // During that engine's startup the branded app name can still be empty, so
  // using it as part of this decision can briefly create a window-level modal
  // barrier. Once the first frame arrives the brand may be available and the
  // cleanup path no longer knows about the anonymous Connecting dialog, leaving
  // a healthy video scene hidden behind a uniform gray barrier.
  //
  // Keep this decision tied only to stable platform/page facts. Both 720p and
  // 1080p therefore use the same uncovered Windows video presentation path.
  return !(isWindowsPlatform && isDesktopPlatform && !isWebPlatform);
}
