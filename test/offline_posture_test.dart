import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Hisaab's privacy claim is that nothing leaves the phone unless the user
/// shares it. These tests make that checkable rather than trusted, which is
/// the whole point of stating it. See spec-27 dec-10.
void main() {
  group('no network surface', () {
    /// Verifies ac-31.
    test('nothing under lib/ imports a networking library', () {
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'run this from the repo root');

      // dart:io is allowed because file export and import need it. Sockets
      // and HTTP clients are not.
      final RegExp banned = RegExp(
        r'''import\s+['"](?:'''
        r'''dart:html'''
        r'''|package:http/'''
        r'''|package:dio/'''
        r'''|package:web_socket_channel/'''
        r'''|package:grpc/'''
        r'''|package:firebase_'''
        r'''|package:googleapis'''
        r''')''',
      );
      final RegExp bannedSymbols = RegExp(
        r'\b(?:HttpClient|Socket\.connect|RawSocket|WebSocket|SecureSocket)\b',
      );

      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String source = entity.readAsStringSync();
        if (banned.hasMatch(source) || bannedSymbols.hasMatch(source)) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these files reach the network, which breaks the claim in the '
            'README and in spec-27 dec-10',
      );
    });

    /// Verifies ac-36.
    test('the main manifest declares no INTERNET permission and no backup', () {
      final String manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      // The permission may appear only as an explicit removal, which strips it
      // if a dependency merges one in.
      final bool declaresInternet = RegExp(
        r'android\.permission\.INTERNET"(?![^>]*tools:node="remove")',
      ).hasMatch(manifest);
      expect(declaresInternet, isFalse);
      expect(manifest, contains('tools:node="remove"'));

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    /// Verifies ac-36.
    test('data extraction rules exclude cloud backup and device transfer', () {
      final String rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(rules, contains('<cloud-backup>'));
      expect(rules, contains('<device-transfer>'));
      for (final String domain in <String>[
        'root',
        'database',
        'sharedpref',
        'file',
      ]) {
        expect(
          RegExp('<exclude domain="$domain" />').allMatches(rules).length,
          2,
          reason: '$domain must be excluded from both backup and transfer',
        );
      }
    });
  });
}
