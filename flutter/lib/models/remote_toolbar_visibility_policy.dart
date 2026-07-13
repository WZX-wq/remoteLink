Future<void> toggleRemoteToolbarVisibility(
  Future<void> Function() toggleToolbar,
) async {
  await toggleToolbar();
}

bool shouldAutoCollapseRemoteToolbar({
  required bool isExpanded,
  required bool isCursorOverImage,
  required bool isDragging,
}) {
  return isExpanded && isCursorOverImage && !isDragging;
}
