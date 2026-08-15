import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/kq_theme.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/chat_model.dart';

class AndroidNotificationEntry {
  const AndroidNotificationEntry({
    required this.key,
    required this.title,
    required this.preview,
    required this.createdAt,
    required this.unreadCount,
  });

  final MessageKey key;
  final String title;
  final String preview;
  final DateTime createdAt;
  final int unreadCount;
}

List<AndroidNotificationEntry> buildAndroidNotificationEntries({
  required Map<MessageKey, MessageBody> messages,
  required Map<int, int> unreadByConnection,
}) {
  final entries = <AndroidNotificationEntry>[];
  for (final conversation in messages.entries) {
    final body = conversation.value;
    if (body.chatMessages.isEmpty) continue;

    final latestMessage = body.chatMessages.first;
    final peerName = body.chatUser.firstName?.trim() ?? '';
    final unreadCount = unreadByConnection[conversation.key.connId] ?? 0;
    entries.add(
      AndroidNotificationEntry(
        key: conversation.key,
        title: peerName.isEmpty ? conversation.key.peerId : peerName,
        preview: latestMessage.text,
        createdAt: latestMessage.createdAt,
        unreadCount: unreadCount < 0 ? 0 : unreadCount,
      ),
    );
  }
  entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return entries;
}

class AndroidNotificationCenterPage extends StatelessWidget {
  const AndroidNotificationCenterPage({super.key});

  Future<void> _openConversation(
    BuildContext context,
    ChatModel chatModel,
    AndroidNotificationEntry entry,
  ) async {
    chatModel.changeCurrentKey(entry.key);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(type: ChatPageType.mobileMain),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final chatModel = gFFI.chatModel;
    return Scaffold(
      backgroundColor: q.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: q.pageGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _NotificationHeader(),
              Expanded(
                child: ChangeNotifierProvider<ChatModel>.value(
                  value: chatModel,
                  child: Consumer<ChatModel>(
                    builder: (context, chatModel, _) {
                      return Obx(() {
                        final totalUnread = chatModel.mobileUnreadSum.value;
                        final unreadByConnection = <int, int>{
                          for (final client in gFFI.serverModel.clients)
                            client.id: client.unreadChatMessageCount.value,
                        };
                        if (totalUnread == 0 && unreadByConnection.isEmpty) {
                          unreadByConnection[ChatModel.clientModeID] = 0;
                        }
                        final entries = buildAndroidNotificationEntries(
                          messages: chatModel.messages,
                          unreadByConnection: unreadByConnection,
                        );
                        if (entries.isEmpty) {
                          return const _NotificationEmptyState();
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            thickness: 1,
                            indent: 56,
                            color: q.line.withValues(alpha: 0.62),
                          ),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _NotificationTimelineRow(
                              entry: entry,
                              onTap: () => _openConversation(
                                context,
                                chatModel,
                                entry,
                              ),
                            );
                          },
                        );
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationHeader extends StatelessWidget {
  const _NotificationHeader();

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: q.ink),
          ),
          Expanded(
            child: Text(
              _notificationText('Notification center'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: q.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationEmptyState extends StatelessWidget {
  const _NotificationEmptyState();

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 52),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: q.iconTile,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: q.iconBorder.withValues(alpha: 0.72),
                ),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: q.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _notificationText('No notifications'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: q.ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _notificationText('New remote messages will appear here'),
              textAlign: TextAlign.center,
              style: TextStyle(color: q.muted, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTimelineRow extends StatelessWidget {
  const _NotificationTimelineRow({
    required this.entry,
    required this.onTap,
  });

  final AndroidNotificationEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: q.iconTile,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: q.iconBorder.withValues(alpha: 0.64),
                    ),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: q.primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: q.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatNotificationTime(entry.createdAt),
                            style: TextStyle(color: q.muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        entry.preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: q.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (entry.unreadCount > 0) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: q.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entry.unreadCount > 99
                          ? '99+'
                          : entry.unreadCount.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(Icons.chevron_right_rounded, color: q.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatNotificationTime(DateTime value) {
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
  return '${value.month}/${value.day}';
}

String _notificationText(String key) {
  switch (key) {
    case 'Notification center':
      return kqLocaleText(zhCn: '通知中心', en: key);
    case 'No notifications':
      return kqLocaleText(zhCn: '暂无通知', en: key);
    case 'New remote messages will appear here':
      return kqLocaleText(zhCn: '新的远程消息会显示在这里', en: key);
    default:
      return translate(key);
  }
}
