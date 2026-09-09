import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The copy rules that catch agent written text more than anything else
/// [per std-24 and std-23]. Checked against the source, because a reviewer
/// reading a diff will not spot an en dash.
void main() {
  List<File> dartFilesUnderLib() {
    final Directory lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run this from the repo root');
    return <File>[
      for (final FileSystemEntity entity in lib.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart')) entity,
    ];
  }

  test('no dash of any kind appears in the source', () {
    // An em dash, an en dash, a figure dash and a horizontal bar. Hyphens
    // inside a compound word are fine and are not matched here.
    final RegExp dashes = RegExp('[—–‒―]');
    final List<String> offenders = <String>[
      for (final File file in dartFilesUnderLib())
        if (dashes.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'use a comma, a colon or parentheses instead [per std-24]',
    );
  });

  test('nothing says please, and nothing asks whether the user is sure', () {
    final RegExp banned = RegExp(
      r'\bplease\b|are you sure',
      caseSensitive: false,
    );
    final List<String> offenders = <String>[
      for (final File file in dartFilesUnderLib())
        if (banned.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'a confirmation names the action and its consequence, and no '
          'label begs',
    );
  });

  test('no dialog button is labelled Yes or No', () {
    final RegExp banned = RegExp(r"""Text\(\s*'(Yes|No|OK|Ok)'\s*\)""");
    final List<String> offenders = <String>[
      for (final File file in dartFilesUnderLib())
        if (banned.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'a button says the action it performs [per std-24]',
    );
  });

  test('no screen formats money by hand', () {
    // A rupee sign followed by an interpolation means a screen built a figure
    // itself instead of going through Money. `lib/helpers/money.dart` is the
    // one place allowed to, because it is that helper.
    final RegExp handRolled = RegExp(r'₹\$\{?[a-zA-Z_]');
    final List<String> offenders = <String>[
      for (final File file in dartFilesUnderLib())
        if (!file.path.endsWith('helpers/money.dart') &&
            handRolled.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'format money through Money.format or Money.formatWithSymbol, which '
          'already group thousands',
    );
  });
}
