Future<void> toggleRemoteToolbarVisibility(
  Future<void> Function() toggleToolbar,
) async {
  await toggleToolbar();
}
