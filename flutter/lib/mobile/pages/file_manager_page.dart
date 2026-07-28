import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';

class FileManagerPage extends StatefulWidget {
  FileManagerPage(
      {Key? key,
      required this.id,
      this.password,
      this.isSharedPassword,
      this.forceRelay})
      : super(key: key);
  final String id;
  final String? password;
  final bool? isSharedPassword;
  final bool? forceRelay;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

enum SelectMode { local, remote, none }

extension SelectModeEq on SelectMode {
  bool eq(bool? currentIsLocal) {
    if (currentIsLocal == null) {
      return false;
    }
    if (currentIsLocal) {
      return this == SelectMode.local;
    } else {
      return this == SelectMode.remote;
    }
  }
}

extension SelectModeExt on Rx<SelectMode> {
  void toggle(bool currentIsLocal) {
    switch (value) {
      case SelectMode.local:
        value = SelectMode.none;
        break;
      case SelectMode.remote:
        value = SelectMode.none;
        break;
      case SelectMode.none:
        if (currentIsLocal) {
          value = SelectMode.local;
        } else {
          value = SelectMode.remote;
        }
        break;
    }
  }
}

class _FileManagerPageState extends State<FileManagerPage> {
  final model = gFFI.fileModel;
  final selectMode = SelectMode.none.obs;

  var showLocal = true;
  var _importingFiles = false;

  FileController get currentFileController =>
      showLocal ? model.localController : model.remoteController;
  FileDirectory get currentDir => currentFileController.directory.value;
  DirectoryOptions get currentOptions => currentFileController.options.value;
  final _uniqueKey = UniqueKey();

  bool get _canPickAndSend =>
      !gFFI.closed &&
      model.localController.directory.value.path.isNotEmpty &&
      model.remoteController.directory.value.path.isNotEmpty;

  bool get _hasActiveTransfer => model.jobController.jobTable.any((job) =>
      job.type == JobType.transfer &&
      (job.state == JobState.inProgress || job.state == JobState.paused));

  @override
  void initState() {
    super.initState();
    gFFI.start(widget.id,
        isFileTransfer: true,
        password: widget.password,
        isSharedPassword: widget.isSharedPassword,
        forceRelay: widget.forceRelay);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.dialogManager
          .showLoading(translate('Connecting...'), onCancel: closeConnection);
    });
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, widget.id);
    WakelockManager.enable(_uniqueKey);
  }

  @override
  void dispose() {
    model.close().whenComplete(() {
      gFFI.close();
      gFFI.dialogManager.dismissAll();
      WakelockManager.disable(_uniqueKey);
    });
    model.jobController.clear();
    super.dispose();
  }

  Future<List<Entry>> _entriesFromPickedFiles(FilePickerResult result) async {
    final entries = <Entry>[];
    for (final picked in result.files) {
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      final source = File(sourcePath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file) continue;

      entries.add(Entry()
        ..entryType = 4
        ..name = picked.name
        ..path = source.path
        ..size = stat.size
        ..modifiedTime = stat.modified.millisecondsSinceEpoch ~/ 1000);
    }
    return entries;
  }

  Future<void> _pickFilesAndSend() async {
    if (_importingFiles) return;
    if (!_canPickAndSend) {
      showToast(kqLocaleText(
        zhCn: '正在准备目标文件夹，请连接完成后再发送。',
        en: 'The destination folder is still loading. Try again once connected.',
      ));
      return;
    }
    if (_hasActiveTransfer) {
      showToast(kqLocaleText(
        zhCn: '当前文件仍在传输，请完成后再选择下一批。',
        en: 'Wait for the current transfer to finish before choosing more files.',
      ));
      return;
    }

    setState(() => _importingFiles = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;

      final entries = await _entriesFromPickedFiles(result);
      if (entries.isEmpty) {
        showToast(kqLocaleText(
          zhCn: '没有可发送的文件，请重新选择。',
          en: 'No files were available to send. Please choose again.',
        ));
        return;
      }

      final selected = SelectedItems(isLocal: true);
      for (final entry in entries) {
        selected.add(entry);
      }
      await model.localController
          .sendFiles(selected, model.remoteController.directoryData());
      if (mounted) {
        setState(() => showLocal = false);
      }
      showToast(kqLocaleText(
        zhCn: '已开始发送 ${entries.length} 个文件',
        en: 'Sending ${entries.length} file(s)',
      ));
    } catch (error, stackTrace) {
      debugPrint('Failed to import selected documents: $error');
      debugPrintStack(stackTrace: stackTrace);
      showToast(kqLocaleText(
        zhCn: '无法读取所选文件，请重新选择后再试。',
        en: 'The selected files could not be read. Please choose them again.',
      ));
    } finally {
      if (mounted) {
        setState(() => _importingFiles = false);
      }
    }
  }

  void _clearSelection() {
    model.localController.selectedItems.clear();
    model.remoteController.selectedItems.clear();
    selectMode.value = SelectMode.none;
    if (mounted) setState(() {});
  }

  Future<void> _sendSelectedItems(SelectedItems items) async {
    final sender =
        items.isLocal ? model.localController : model.remoteController;
    final destination =
        items.isLocal ? model.remoteController : model.localController;
    if (destination.directory.value.path.isEmpty) {
      showToast(kqLocaleText(
        zhCn: '目标文件夹尚未准备好，请稍后重试。',
        en: 'The destination folder is not ready yet. Try again shortly.',
      ));
      return;
    }
    await sender.sendFiles(items, destination.directoryData());
    final itemCount = items.items.length;
    _clearSelection();
    if (mounted) {
      setState(() => showLocal = destination.isLocal);
    }
    showToast(kqLocaleText(
      zhCn: '已开始传输 $itemCount 个项目',
      en: 'Transferring $itemCount item(s)',
    ));
  }

  Future<void> _deleteSelectedItems(SelectedItems items) async {
    final controller =
        items.isLocal ? model.localController : model.remoteController;
    await controller.removeAction(items);
    _clearSelection();
  }

  String _displayDirectory(FileController controller) {
    final directory = controller.directory.value.path;
    if (directory.isEmpty) {
      return kqLocaleText(zhCn: '正在加载文件夹', en: 'Loading folder');
    }
    final normalized = directory.replaceAll('\\', '/');
    if (normalized == '/') return normalized;
    final pieces = normalized.split('/').where((item) => item.isNotEmpty);
    return pieces.isEmpty ? directory : pieces.last;
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
      onWillPop: () async {
        if (selectMode.value != SelectMode.none) {
          _clearSelection();
          return false;
        }
        if (currentFileController.history.isNotEmpty) {
          currentFileController.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: translate('Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => clientClose(gFFI.sessionId, gFFI),
          ),
          title: Text(kqLocaleText(zhCn: '文件传输', en: 'File transfer')),
          actions: [
            Obx(() => IconButton(
                  tooltip: kqLocaleText(
                      zhCn: '选择并发送文件', en: 'Choose and send files'),
                  icon: _importingFiles
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  onPressed: _importingFiles || _hasActiveTransfer
                      ? null
                      : _pickFilesAndSend,
                )),
            IconButton(
              tooltip: translate('Refresh File'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => currentFileController.refresh(),
            ),
            PopupMenuButton<String>(
                tooltip: kqLocaleText(zhCn: '文件选项', en: 'File options'),
                icon: const Icon(Icons.more_horiz_rounded),
                itemBuilder: (context) {
                  return [
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(Icons.checklist_rounded,
                              color: Theme.of(context).iconTheme.color),
                          const SizedBox(width: 8),
                          Text(translate("Multi Select"))
                        ],
                      ),
                      value: "select",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(Icons.create_new_folder_outlined,
                              color: Theme.of(context).iconTheme.color),
                          const SizedBox(width: 8),
                          Text(translate("Create Folder"))
                        ],
                      ),
                      value: "folder",
                    ),
                    PopupMenuItem(
                      enabled: currentDir.path != "/",
                      child: Row(
                        children: [
                          Icon(
                              currentOptions.showHidden
                                  ? Icons.check_box_outlined
                                  : Icons.check_box_outline_blank,
                              color: Theme.of(context).iconTheme.color),
                          const SizedBox(width: 8),
                          Text(translate("Show Hidden Files"))
                        ],
                      ),
                      value: "hidden",
                    )
                  ];
                },
                onSelected: (v) async {
                  if (v == "select") {
                    model.localController.selectedItems.clear();
                    model.remoteController.selectedItems.clear();
                    selectMode.toggle(showLocal);
                    setState(() {});
                  } else if (v == "folder") {
                    final name = TextEditingController();
                    String? errorText;
                    gFFI.dialogManager.show((setState, close, context) {
                      name.addListener(() {
                        if (errorText != null) {
                          setState(() {
                            errorText = null;
                          });
                        }
                      });
                      return CustomAlertDialog(
                          title: Text(translate("Create Folder")),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText:
                                      translate("Please enter the folder name"),
                                  errorText: errorText,
                                ),
                                controller: name,
                              ).workaroundFreezeLinuxMint(),
                            ],
                          ),
                          actions: [
                            dialogButton("Cancel",
                                onPressed: () => close(false), isOutline: true),
                            dialogButton("OK", onPressed: () {
                              if (name.value.text.isNotEmpty) {
                                if (!PathUtil.validName(
                                    name.value.text,
                                    currentFileController
                                        .options.value.isWindows)) {
                                  setState(() {
                                    errorText =
                                        translate("Invalid folder name");
                                  });
                                  return;
                                }
                                currentFileController.createDir(PathUtil.join(
                                    currentDir.path,
                                    name.value.text,
                                    currentOptions.isWindows));
                                close();
                              }
                            })
                          ]);
                    });
                  } else if (v == "hidden") {
                    currentFileController.toggleShowHidden();
                  }
                }),
          ],
        ),
        body: Column(children: [
          _buildLocationSelector(),
          if (_importingFiles) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: FileManagerView(
              controller:
                  showLocal ? model.localController : model.remoteController,
              selectMode: selectMode,
            ),
          ),
        ]),
        bottomNavigationBar: _buildTransferPanel(),
      ));

  Widget _buildLocationSelector() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(children: [
        Expanded(
          child: _FileLocationTab(
            selected: showLocal,
            icon: Icons.phone_iphone_rounded,
            label: kqLocaleText(zhCn: '我的文件', en: 'My files'),
            onTap: () => setState(() => showLocal = true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FileLocationTab(
            selected: !showLocal,
            icon: Icons.desktop_windows_rounded,
            label: kqLocaleText(zhCn: '对方文件', en: 'Remote files'),
            onTap: () => setState(() => showLocal = false),
          ),
        ),
      ]),
    );
  }

  Widget _buildTransferPanel() {
    return Obx(() {
      final selectedItems = getActiveSelectedItems();
      final jobTable = model.jobController.jobTable;
      if (selectedItems != null && selectedItems.items.isNotEmpty) {
        final isSendingToRemote = selectedItems.isLocal;
        final destination =
            isSendingToRemote ? model.remoteController : model.localController;
        return _FileTransferPanel(
          icon: isSendingToRemote ? Icons.send_rounded : Icons.download_rounded,
          title: kqLocaleText(
            zhCn: '已选择 ${selectedItems.items.length} 个项目',
            en: '${selectedItems.items.length} item(s) selected',
          ),
          subtitle: kqLocaleText(
            zhCn:
                '${isSendingToRemote ? '发送到' : '保存到'} ${_displayDirectory(destination)}',
            en: '${isSendingToRemote ? 'Send to' : 'Save to'} ${_displayDirectory(destination)}',
          ),
          primaryLabel: isSendingToRemote
              ? kqLocaleText(zhCn: '发送', en: 'Send')
              : kqLocaleText(zhCn: '保存', en: 'Save'),
          primaryIcon:
              isSendingToRemote ? Icons.send_rounded : Icons.download_rounded,
          onPrimary: destination.directory.value.path.isEmpty
              ? null
              : () => _sendSelectedItems(selectedItems),
          secondary: IconButton(
            tooltip: translate('Delete'),
            onPressed: () => _deleteSelectedItems(selectedItems),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          onDismiss: _clearSelection,
        );
      }

      if (jobTable.isEmpty) {
        return _FileTransferPanel(
          icon: Icons.upload_file_rounded,
          title: kqLocaleText(zhCn: '选择文件并发送', en: 'Choose files to send'),
          subtitle: _canPickAndSend
              ? kqLocaleText(
                  zhCn: '文件会直接发送到 ${_displayDirectory(model.remoteController)}',
                  en: 'Files will be sent to ${_displayDirectory(model.remoteController)}',
                )
              : kqLocaleText(
                  zhCn: '正在准备远端文件夹',
                  en: 'Preparing the remote folder',
                ),
          primaryLabel: kqLocaleText(zhCn: '选择文件', en: 'Choose files'),
          primaryIcon: Icons.add_rounded,
          onPrimary: _canPickAndSend && !_importingFiles && !_hasActiveTransfer
              ? _pickFilesAndSend
              : null,
        );
      }

      final activeJob = jobTable
              .firstWhereOrNull((job) => job.state == JobState.inProgress) ??
          jobTable.firstWhereOrNull((job) => job.state == JobState.error) ??
          jobTable.firstWhereOrNull((job) => job.state == JobState.paused) ??
          jobTable.last;
      switch (activeJob.state) {
        case JobState.inProgress:
          return _FileTransferPanel(
            icon: Icons.sync_rounded,
            title: kqLocaleText(
              zhCn: '正在传输 ${activeJob.fileName}',
              en: 'Transferring ${activeJob.fileName}',
            ),
            subtitle: activeJob.totalSize > 0
                ? '${activeJob.percentText}  ${readableFileSize(activeJob.finishedSize.toDouble())} / ${readableFileSize(activeJob.totalSize.toDouble())}  ${readableFileSize(activeJob.speed)}/s'
                : '${translate("Waiting")}  ${readableFileSize(activeJob.speed)}/s',
            progress: activeJob.totalSize > 0 ? activeJob.percent : null,
            primaryLabel: translate('Cancel'),
            primaryIcon: Icons.close_rounded,
            onPrimary: () => model.jobController.cancelJob(activeJob.id),
          );
        case JobState.done:
          return _FileTransferPanel(
            icon: Icons.check_circle_outline_rounded,
            title: kqLocaleText(zhCn: '传输完成', en: 'Transfer complete'),
            subtitle: activeJob.fileName,
            primaryLabel: translate('Close'),
            primaryIcon: Icons.done_rounded,
            onPrimary: jobTable.clear,
          );
        case JobState.error:
          return _FileTransferPanel(
            icon: Icons.error_outline_rounded,
            title: kqLocaleText(zhCn: '传输未完成', en: 'Transfer incomplete'),
            subtitle: activeJob.display(),
            primaryLabel: translate('Close'),
            primaryIcon: Icons.close_rounded,
            onPrimary: jobTable.clear,
          );
        case JobState.paused:
          return _FileTransferPanel(
            icon: Icons.pause_circle_outline_rounded,
            title: translate('Paused'),
            subtitle: activeJob.fileName,
            primaryLabel: translate('Resume'),
            primaryIcon: Icons.play_arrow_rounded,
            onPrimary: () => model.jobController.resumeJob(activeJob.id),
            secondary: IconButton(
              tooltip: translate('Cancel'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => model.jobController.cancelJob(activeJob.id),
            ),
          );
        case JobState.none:
          return const SizedBox.shrink();
      }
    });
  }

  SelectedItems? getActiveSelectedItems() {
    final localSelectedItems = model.localController.selectedItems;
    final remoteSelectedItems = model.remoteController.selectedItems;

    if (localSelectedItems.items.isNotEmpty &&
        remoteSelectedItems.items.isNotEmpty) {
      debugPrint("Wrong SelectedItems state, reset");
      localSelectedItems.clear();
      remoteSelectedItems.clear();
      return null;
    }

    if (localSelectedItems.items.isEmpty && remoteSelectedItems.items.isEmpty) {
      return null;
    }

    if (localSelectedItems.items.length > remoteSelectedItems.items.length) {
      return localSelectedItems;
    } else {
      return remoteSelectedItems;
    }
  }
}

class _FileLocationTab extends StatelessWidget {
  const _FileLocationTab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: 0.12) : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: selected ? colors.primary : null),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? colors.primary : colors.onSurface,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FileTransferPanel extends StatelessWidget {
  const _FileTransferPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.progress,
    this.secondary,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final double? progress;
  final Widget? secondary;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (progress != null || onPrimary == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(value: progress),
              ),
            Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 9),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (secondary != null) secondary!,
              if (secondary != null) const SizedBox(width: 4),
              if (onDismiss != null) ...[
                IconButton(
                  tooltip: translate('Close'),
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
              ],
              FilledButton.icon(
                onPressed: onPrimary,
                icon: Icon(primaryIcon, size: 18),
                label: Text(primaryLabel),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class FileManagerView extends StatefulWidget {
  final FileController controller;
  final Rx<SelectMode> selectMode;

  FileManagerView({required this.controller, required this.selectMode});

  @override
  State<StatefulWidget> createState() => _FileManagerViewState();
}

class _FileManagerViewState extends State<FileManagerView> {
  final _listScrollController = ScrollController();
  final _breadCrumbScroller = ScrollController();
  late final ascending = Rx<bool>(controller.sortAscending);

  bool get isLocal => widget.controller.isLocal;
  FileController get controller => widget.controller;
  SelectedItems get _selectedItems => widget.controller.selectedItems;

  @override
  void initState() {
    super.initState();
    controller.directory.listen((e) => breadCrumbScrollToEnd());
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      headTools(),
      Expanded(child: Obx(() {
        final entries = controller.directory.value.entries;
        if (entries.isEmpty) {
          return _emptyDirectory();
        }
        return ListView.builder(
          controller: _listScrollController,
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index >= entries.length) {
              return listTail();
            }
            var selected = false;
            if (widget.selectMode.value != SelectMode.none) {
              selected = _selectedItems.items.contains(entries[index]);
            }

            final sizeStr = entries[index].isFile
                ? readableFileSize(entries[index].size.toDouble())
                : "";

            final showCheckBox = () {
              return widget.selectMode.value != SelectMode.none &&
                  widget.selectMode.value.eq(controller.selectedItems.isLocal);
            }();
            return Material(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08)
                  : Colors.transparent,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                leading: SizedBox(
                  width: 40,
                  child: entries[index].isDrive
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Image(
                              image: iconHardDrive,
                              fit: BoxFit.scaleDown,
                              color: Theme.of(context)
                                  .iconTheme
                                  .color
                                  ?.withValues(alpha: 0.7)))
                      : Icon(
                          entries[index].isFile
                              ? Icons.insert_drive_file_outlined
                              : Icons.folder_outlined,
                          color: entries[index].isFile
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.tertiary,
                          size: 28),
                ),
                title: Text(
                  entries[index].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selected,
                subtitle: entries[index].isDrive
                    ? null
                    : Text(
                        "${entries[index].lastModified().toString().replaceAll(".000", "")}   $sizeStr",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: MyTheme.darkGray),
                      ),
                trailing: entries[index].isDrive
                    ? null
                    : showCheckBox
                        ? Checkbox(
                            value: selected,
                            onChanged: (v) {
                              if (v == null) return;
                              if (v && !selected) {
                                _selectedItems.add(entries[index]);
                              } else if (!v && selected) {
                                _selectedItems.remove(entries[index]);
                              }
                              setState(() {});
                            })
                        : PopupMenuButton<String>(
                            tooltip: "",
                            icon: Icon(Icons.more_vert),
                            itemBuilder: (context) {
                              return [
                                PopupMenuItem(
                                  child: Text(translate("Delete")),
                                  value: "delete",
                                ),
                                PopupMenuItem(
                                  child: Text(translate("Multi Select")),
                                  value: "multi_select",
                                ),
                                if (!entries[index].isDrive &&
                                    versionCmp(gFFI.ffiModel.pi.version,
                                            "1.3.0") >=
                                        0)
                                  PopupMenuItem(
                                    child: Text(translate("Rename")),
                                    value: "rename",
                                  )
                              ];
                            },
                            onSelected: (v) {
                              if (v == "delete") {
                                final items = SelectedItems(isLocal: isLocal);
                                items.add(entries[index]);
                                controller.removeAction(items);
                              } else if (v == "multi_select") {
                                _selectedItems.clear();
                                widget.selectMode.toggle(isLocal);
                                setState(() {});
                              } else if (v == "rename") {
                                controller.renameAction(
                                    entries[index], isLocal);
                              }
                            }),
                onTap: () {
                  if (showCheckBox) {
                    if (selected) {
                      _selectedItems.remove(entries[index]);
                    } else {
                      _selectedItems.add(entries[index]);
                    }
                    setState(() {});
                    return;
                  }
                  if (entries[index].isDirectory || entries[index].isDrive) {
                    controller.openDirectory(entries[index].path);
                  } else {
                    if (widget.selectMode.value != SelectMode.none &&
                        !widget.selectMode.value.eq(isLocal)) {
                      return;
                    }
                    if (widget.selectMode.value == SelectMode.none) {
                      widget.selectMode.value =
                          isLocal ? SelectMode.local : SelectMode.remote;
                    }
                    _selectedItems.clear();
                    _selectedItems.add(entries[index]);
                    setState(() {});
                  }
                },
                onLongPress: entries[index].isDrive
                    ? null
                    : () {
                        _selectedItems.clear();
                        widget.selectMode.toggle(isLocal);
                        if (widget.selectMode.value != SelectMode.none) {
                          _selectedItems.add(entries[index]);
                        }
                        setState(() {});
                      },
              ),
            );
          },
        );
      }))
    ]);
  }

  void breadCrumbScrollToEnd() {
    Future.delayed(Duration(milliseconds: 200), () {
      if (_breadCrumbScroller.hasClients) {
        _breadCrumbScroller.animateTo(
            _breadCrumbScroller.position.maxScrollExtent,
            duration: Duration(milliseconds: 200),
            curve: Curves.fastLinearToSlowEaseIn);
      }
    });
  }

  Widget _emptyDirectory() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            Icons.folder_open_outlined,
            size: 46,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            kqLocaleText(zhCn: '此文件夹为空', en: 'This folder is empty'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            isLocal
                ? kqLocaleText(
                    zhCn: '使用底部的“选择文件”即可发送给对方。',
                    en: 'Use “Choose files” below to send files to the remote device.',
                  )
                : kqLocaleText(
                    zhCn: '可在这里创建文件夹，或从手机发送文件到当前目录。',
                    en: 'Create a folder here or send files from your phone to this directory.',
                  ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }

  Widget headTools() => Container(
          child: Row(
        children: [
          Expanded(child: Obx(() {
            final home = controller.options.value.home;
            final isWindows = controller.options.value.isWindows;
            return BreadCrumb(
              items: getPathBreadCrumbItems(controller.shortPath, isWindows,
                  () => controller.goToHomeDirectory(), (list) {
                var path = "";
                if (home.startsWith(list[0])) {
                  // absolute path
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                } else {
                  path += home;
                  for (var item in list) {
                    path = PathUtil.join(path, item, isWindows);
                  }
                }
                controller.openDirectory(path);
              }),
              divider: Icon(Icons.chevron_right),
              overflow: ScrollableOverflow(controller: _breadCrumbScroller),
            );
          })),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: controller.goBack,
              ),
              IconButton(
                icon: Icon(Icons.arrow_upward),
                onPressed: controller.goToParentDirectory,
              ),
              PopupMenuButton<SortBy>(
                  tooltip: "",
                  icon: Icon(Icons.sort),
                  itemBuilder: (context) {
                    return SortBy.values
                        .map((e) => PopupMenuItem(
                              child: Text(translate(e.toString())),
                              value: e,
                            ))
                        .toList();
                  },
                  onSelected: (sortBy) {
                    // If selecting the same sort option, flip the order
                    // If selecting a different sort option, use ascending order
                    if (controller.sortBy.value == sortBy) {
                      ascending.value = !controller.sortAscending;
                    } else {
                      ascending.value = true;
                    }
                    controller.changeSortStyle(sortBy,
                        ascending: ascending.value);
                  }),
            ],
          )
        ],
      ));

  Widget listTail() => Obx(() => Container(
        height: 100,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(30, 5, 30, 0),
              child: Text(
                controller.directory.value.path,
                style: TextStyle(color: MyTheme.darkGray),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(2),
              child: Text(
                "${translate("Total")}: ${controller.directory.value.entries.length} ${translate("items")}",
                style: TextStyle(color: MyTheme.darkGray),
              ),
            )
          ],
        ),
      ));

  List<BreadCrumbItem> getPathBreadCrumbItems(String shortPath, bool isWindows,
      void Function() onHome, void Function(List<String>) onPressed) {
    final list = PathUtil.split(shortPath, isWindows);
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
        icon: Icon(Icons.home_filled),
        onPressed: onHome,
      ))
    ];
    breadCrumbList.addAll(list.asMap().entries.map((e) => BreadCrumbItem(
        content: TextButton(
            child: Text(e.value),
            style:
                ButtonStyle(minimumSize: MaterialStateProperty.all(Size(0, 0))),
            onPressed: () => onPressed(list.sublist(0, e.key + 1))))));
    return breadCrumbList;
  }
}
