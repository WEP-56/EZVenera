import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/network/network_client_factory.dart';
import 'package:ezvenera/src/settings/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('ezv_settings_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => supportDir.path,
        );
    await SettingsController.instance.initialize();
  });

  tearDownAll(() async {
    await supportDir.delete(recursive: true);
  });

  group('SettingsController.isValidProxyUrl', () {
    test('accepts http(s) URLs with host', () {
      expect(SettingsController.isValidProxyUrl('http://192.168.2.153:16492'),
          isTrue);
      expect(
        SettingsController.isValidProxyUrl('https://proxy.example.com'),
        isTrue,
      );
    });

    test('rejects non-http schemes, missing host, and garbage', () {
      expect(SettingsController.isValidProxyUrl('ftp://proxy.example.com'),
          isFalse);
      expect(SettingsController.isValidProxyUrl('http://'), isFalse);
      expect(SettingsController.isValidProxyUrl('not a url'), isFalse);
      expect(SettingsController.isValidProxyUrl(''), isFalse);
    });
  });

  group('SettingsController.customProxyAuthority', () {
    test('keeps explicit port', () {
      expect(
        SettingsController.customProxyAuthority('http://192.168.2.153:16492'),
        '192.168.2.153:16492',
      );
    });

    test('defaults port by scheme', () {
      expect(
        SettingsController.customProxyAuthority('https://proxy.example.com'),
        'proxy.example.com:443',
      );
      expect(
        SettingsController.customProxyAuthority('http://proxy.example.com'),
        'proxy.example.com:80',
      );
    });

    test('brackets IPv6 hosts for findProxy', () {
      expect(
        SettingsController.customProxyAuthority('http://[::1]:8080'),
        '[::1]:8080',
      );
    });

    test('returns null for invalid input', () {
      expect(SettingsController.customProxyAuthority('not a url'), isNull);
      expect(SettingsController.customProxyAuthority('http://'), isNull);
    });
  });

  group('SettingsController proxy persistence (ADR-NW-2)', () {
    test('credentials are stripped from persisted settings and backups', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.custom);
      await controller.setProxyUrl('http://user:secret@192.168.2.153:16492');

      // The in-memory value keeps the credentials for the current session.
      expect(controller.proxyUrl, 'http://user:secret@192.168.2.153:16492');

      // Backups never contain them.
      final backup = controller.toBackupJson();
      expect(backup['proxyMode'], 'custom');
      expect(backup['proxyUrl'], 'http://192.168.2.153:16492');

      // The on-disk settings file never contains them either.
      final file = File(
        '${supportDir.path}/settings/app_settings.json',
      );
      final onDisk = jsonDecode(await file.readAsString()) as Map<String,
          dynamic>;
      expect(onDisk['proxyUrl'], 'http://192.168.2.153:16492');
      expect(await file.readAsString(), isNot(contains('secret')));

      await controller.setProxyMode(ProxyMode.system);
      await controller.setProxyUrl('');
    });

    test('restoring a backup re-sanitizes the URL', () async {
      final controller = SettingsController.instance;
      await controller.restoreFromBackupJson(<String, dynamic>{
        'proxyMode': 'custom',
        'proxyUrl': 'http://user:secret@proxy.example.com:8080',
      });
      expect(controller.proxyUrl, 'http://proxy.example.com:8080');
      expect(controller.proxyMode, ProxyMode.custom);

      await controller.setProxyMode(ProxyMode.system);
      await controller.setProxyUrl('');
    });

    test('reset returns proxy settings to defaults', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.custom);
      await controller.setProxyUrl('http://proxy.example.com:8080');
      await controller.reset();
      expect(controller.proxyMode, ProxyMode.system);
      expect(controller.proxyUrl, '');
    });
  });

  group('NetworkClientFactory.resolveProxyConfig', () {
    test('system mode reports no custom proxy', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.system);
      final config = NetworkClientFactory.instance.resolveProxyConfig();
      expect(config.mode, ProxyMode.system);
      expect(config.usesCustomProxy, isFalse);
      expect(config.customAuthority, isNull);
    });

    test('custom mode exposes the proxy authority', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.custom);
      await controller.setProxyUrl('http://192.168.2.153:16492');
      final config = NetworkClientFactory.instance.resolveProxyConfig();
      expect(config.mode, ProxyMode.custom);
      expect(config.usesCustomProxy, isTrue);
      expect(config.customAuthority, '192.168.2.153:16492');

      await controller.setProxyMode(ProxyMode.system);
      await controller.setProxyUrl('');
    });

    test('invalid custom URL falls back to system behavior', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.custom);
      // Bypass the UI by writing an invalid URL through the raw setter.
      await controller.setProxyUrl('not a url');
      final config = NetworkClientFactory.instance.resolveProxyConfig();
      expect(config.mode, ProxyMode.system);
      expect(config.usesCustomProxy, isFalse);

      await controller.setProxyMode(ProxyMode.system);
      await controller.setProxyUrl('');
    });

    test('off mode disables proxying entirely', () async {
      final controller = SettingsController.instance;
      await controller.setProxyMode(ProxyMode.off);
      final config = NetworkClientFactory.instance.resolveProxyConfig();
      expect(config.mode, ProxyMode.off);
      expect(config.customAuthority, isNull);

      await controller.setProxyMode(ProxyMode.system);
    });
  });
}
