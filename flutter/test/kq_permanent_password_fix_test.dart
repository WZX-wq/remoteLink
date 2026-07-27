// iOS 永久密码修复测试用例
// 文件位置: flutter/test/kq_permanent_password_fix_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/server_model.dart';

void main() {
  group('kqNormalizeVerificationCode 测试', () {
    test('应该移除空格', () {
      expect(kqNormalizeVerificationCode('ab cd ef'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('  test  '), equals('test'));
      expect(kqNormalizeVerificationCode('a b c d e f g'), equals('abcdef'));
    });

    test('应该转换为小写', () {
      expect(kqNormalizeVerificationCode('ABCDEF'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('AbCdEf'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('TEST01'), equals('test01'));
    });

    test('应该截断到6位', () {
      expect(kqNormalizeVerificationCode('abcdefgh'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('1234567890'), equals('123456'));
      expect(kqNormalizeVerificationCode('gtbeenxy'), equals('gtbeen'));
    });

    test('应该处理组合场景', () {
      // 大小写 + 空格 + 超长
      expect(kqNormalizeVerificationCode('AB CD EF GH'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('  GTBEEN XY  '), equals('gtbeen'));
      expect(kqNormalizeVerificationCode('Test 01 234'), equals('test01'));
    });

    test('应该处理短密码', () {
      expect(kqNormalizeVerificationCode('abc'), equals('abc'));
      expect(kqNormalizeVerificationCode('12'), equals('12'));
      expect(kqNormalizeVerificationCode('a'), equals('a'));
    });

    test('应该处理空字符串', () {
      expect(kqNormalizeVerificationCode(''), equals(''));
      expect(kqNormalizeVerificationCode('   '), equals(''));
    });

    test('应该处理特殊字符（不移除）', () {
      // 注意：只移除空白字符，不移除其他特殊字符
      expect(kqNormalizeVerificationCode('abc-def'), equals('abc-de'));
      expect(kqNormalizeVerificationCode('test_01'), equals('test_0'));
    });

    test('应该处理Unicode字符', () {
      expect(kqNormalizeVerificationCode('测试test'), equals('测试test'));
      expect(kqNormalizeVerificationCode('café'), equals('café'));
    });
  });

  group('密码长度常量测试', () {
    test('验证码长度应为6', () {
      expect(kqVerificationCodeLength, equals(6));
    });
  });

  group('回归测试 - 真实场景', () {
    test('场景1: 用户设置8位密码后被截断', () {
      const originalPassword = 'gtbeenxy'; // 8位
      const normalized = 'gtbeen'; // 预期截断到6位

      expect(kqNormalizeVerificationCode(originalPassword), equals(normalized));
    });

    test('场景2: iOS自动首字母大写', () {
      const userInput = 'Gtbeen'; // iOS可能自动大写首字母
      const expected = 'gtbeen';

      expect(kqNormalizeVerificationCode(userInput), equals(expected));
    });

    test('场景3: 用户复制粘贴带空格的密码', () {
      const copiedPassword = ' gtbeen '; // 复制时可能带空格
      const expected = 'gtbeen';

      expect(kqNormalizeVerificationCode(copiedPassword), equals(expected));
    });

    test('场景4: Android端输入大写密码', () {
      const androidInput = 'GTBEEN';
      const iosStored = 'gtbeen';

      // 验证归一化后相同
      expect(
        kqNormalizeVerificationCode(androidInput),
        equals(kqNormalizeVerificationCode(iosStored)),
      );
    });

    test('场景5: 密码包含数字', () {
      const password = 'test01';

      expect(kqNormalizeVerificationCode(password), equals('test01'));
      expect(kqNormalizeVerificationCode('TEST 01'), equals('test01'));
      expect(kqNormalizeVerificationCode('Test01234'), equals('test01'));
    });
  });

  group('边界条件测试', () {
    test('恰好6位', () {
      expect(kqNormalizeVerificationCode('abcdef'), equals('abcdef'));
      expect(kqNormalizeVerificationCode('123456'), equals('123456'));
    });

    test('少于6位', () {
      expect(kqNormalizeVerificationCode('abc'), equals('abc'));
      expect(kqNormalizeVerificationCode('12345'), equals('12345'));
    });

    test('远超6位', () {
      const veryLongPassword = 'abcdefghijklmnopqrstuvwxyz0123456789';
      expect(kqNormalizeVerificationCode(veryLongPassword), equals('abcdef'));
    });

    test('全空格', () {
      expect(kqNormalizeVerificationCode('      '), equals(''));
    });

    test('多种空白字符', () {
      expect(kqNormalizeVerificationCode('a\tb\nc\rd'), equals('abcd'));
    });
  });
}
