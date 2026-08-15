import 'dart:io';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter_hbb/mobile/pages/android_notification_center_page.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android notification projection', () {
    test('returns no entries when there are no real messages', () {
      final entries = buildAndroidNotificationEntries(
        messages: <MessageKey, MessageBody>{},
        unreadByConnection: const <int, int>{},
      );

      expect(entries, isEmpty);
    });

    test('sorts real conversations by newest message', () {
      final olderKey = MessageKey('older-peer', 4);
      final newerKey = MessageKey('newer-peer', 9);
      final olderUser = ChatUser(id: 'older-peer', firstName: 'Older device');
      final newerUser = ChatUser(id: 'newer-peer', firstName: 'Newer device');
      final olderMessage = ChatMessage(
        text: 'Older real message',
        user: olderUser,
        createdAt: DateTime(2026, 8, 13, 9),
      );
      final newerMessage = ChatMessage(
        text: 'Newest real message',
        user: newerUser,
        createdAt: DateTime(2026, 8, 13, 10),
      );

      final entries = buildAndroidNotificationEntries(
        messages: <MessageKey, MessageBody>{
          olderKey: MessageBody(olderUser, <ChatMessage>[olderMessage]),
          newerKey: MessageBody(newerUser, <ChatMessage>[newerMessage]),
        },
        unreadByConnection: const <int, int>{9: 2},
      );

      expect(entries.map((entry) => entry.key), <MessageKey>[
        newerKey,
        olderKey,
      ]);
      expect(entries.first.title, 'Newer device');
      expect(entries.first.preview, 'Newest real message');
      expect(entries.first.createdAt, DateTime(2026, 8, 13, 10));
      expect(entries.first.unreadCount, 2);
    });

    test('skips empty conversations and falls back to the peer ID', () {
      final emptyKey = MessageKey('empty-peer', 3);
      final fallbackKey = MessageKey('fallback-peer', 8);
      final emptyUser = ChatUser(id: 'empty-peer', firstName: 'Empty device');
      final fallbackUser = ChatUser(id: 'fallback-peer', firstName: '   ');

      final entries = buildAndroidNotificationEntries(
        messages: <MessageKey, MessageBody>{
          emptyKey: MessageBody(emptyUser, <ChatMessage>[]),
          fallbackKey: MessageBody(
            fallbackUser,
            <ChatMessage>[
              ChatMessage(
                text: 'Available message',
                user: fallbackUser,
                createdAt: DateTime(2026, 8, 13, 11),
              ),
            ],
          ),
        },
        unreadByConnection: const <int, int>{8: -1},
      );

      expect(entries, hasLength(1));
      expect(entries.single.key, fallbackKey);
      expect(entries.single.title, 'fallback-peer');
      expect(entries.single.unreadCount, 0);
    });
  });

  test('Android notification center renders real timeline states', () {
    final page = File(
      'lib/mobile/pages/android_notification_center_page.dart',
    ).readAsStringSync();

    expect(page, contains('class AndroidNotificationCenterPage'));
    expect(page, contains("_notificationText('Notification center')"));
    expect(page, contains("_notificationText('No notifications')"));
    expect(
      page,
      contains("_notificationText('New remote messages will appear here')"),
    );
    expect(page, contains('KqTheme.of(context)'));
    expect(page, contains('chatModel.mobileUnreadSum.value'));
    expect(page, contains('maxLines: 2'));
    expect(page, contains('chatModel.changeCurrentKey(entry.key)'));
    expect(page, contains('ChatPage(type: ChatPageType.mobileMain)'));
    expect(page, isNot(contains('Device connected successfully')));
    expect(page, isNot(contains('Remote operation completed')));
  });

  test('Android account routes notifications without changing other platforms',
      () {
    final account =
        File('lib/mobile/pages/account_page.dart').readAsStringSync();

    expect(
      account,
      contains("import 'android_notification_center_page.dart';"),
    );
    expect(
      account,
      contains('builder: (_) => const AndroidNotificationCenterPage()'),
    );
    expect(account, contains('onNotificationTap: isAndroid'));
    expect(account, contains('? _openNotifications'));
    expect(
      account,
      contains(": () => showToast(_mineText('No notifications'))"),
    );
    expect(account, isNot(contains('ChatPage(type: ChatPageType.mobileMain)')));
  });
}
