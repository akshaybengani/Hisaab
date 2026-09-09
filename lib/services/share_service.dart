import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

/// Re-exported so a caller, and a test standing in for the platform, does not
/// have to import the plugin alongside this facade.
export 'package:share_plus/share_plus.dart' show ShareParams, XFile;

/// Opens a URL and says whether anything handled it.
typedef UrlOpener = Future<bool> Function(Uri url);

/// Hands something to the system share sheet.
typedef Sharer = Future<void> Function(ShareParams params);

/// Where a message is about to go.
enum ShareRoute {
  /// Straight into a WhatsApp chat, because a number is saved.
  whatsApp,

  /// The system share sheet, so the user picks.
  shareSheet,
}

/// Builds the `wa.me` link that opens a chat with a message already typed.
///
/// Kept as pure functions with no plugin behind them, so the number handling
/// and the escaping are asserted in a plain unit test rather than only on a
/// phone.
abstract final class WhatsAppLink {
  /// India, because that is where this book is kept. A number stored with its
  /// own country code keeps it.
  static const String defaultCountryCode = '91';

  /// The shortest string that can be a subscriber number, and the longest an
  /// E.164 number can be.
  static const int _minDigits = 10;
  static const int _maxDigits = 15;

  /// Turns whatever was typed into the contact field into the digits `wa.me`
  /// wants, or null where it cannot be one.
  ///
  /// Spaces, brackets and hyphens go. A number written with `+` or `00`
  /// already carries its country code and keeps it. Otherwise a leading trunk
  /// zero is dropped and a bare ten digit number gets [countryCode] in front,
  /// which is the only guess made here and the one that is right for every
  /// number in this book.
  static String? digits(
    String? phone, {
    String countryCode = defaultCountryCode,
  }) {
    if (phone == null) return null;
    final String typed = phone.trim();
    if (typed.isEmpty) return null;
    final bool international = typed.startsWith('+') || typed.startsWith('00');
    String number = typed.replaceAll(RegExp(r'\D'), '');
    if (typed.startsWith('00')) {
      number = number.substring(2);
    } else if (!international) {
      while (number.startsWith('0')) {
        number = number.substring(1);
      }
      if (number.length == _minDigits) number = '$countryCode$number';
    }
    if (number.length < _minDigits || number.length > _maxDigits) return null;
    return number;
  }

  /// The link, or null where no usable number is saved and the share sheet has
  /// to be used instead.
  ///
  /// The message is percent-encoded whole, so a newline travels as `%0A`, a
  /// space as `%20` and the rupee sign as its UTF-8 bytes. Dart's own query
  /// building writes a space as `+`, which WhatsApp shows literally, so it is
  /// deliberately not used here.
  static Uri? forPhone(
    String? phone,
    String message, {
    String countryCode = defaultCountryCode,
  }) {
    final String? number = digits(phone, countryCode: countryCode);
    if (number == null) return null;
    return Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
    );
  }

  /// The same thing for a person, which is how every caller holds it.
  static Uri? forPerson(Person person, String message) =>
      forPhone(person.phone, message);

  /// Which way a message to [person] will go, before anything is sent.
  static ShareRoute routeFor(Person person) => digits(person.phone) == null
      ? ShareRoute.shareSheet
      : ShareRoute.whatsApp;
}

/// The one place the app hands something to another app.
///
/// Text goes into a WhatsApp chat where a number is saved and to the share
/// sheet where one is not. A file always goes to the share sheet, because
/// `wa.me` cannot carry an attachment.
///
/// Nothing here uploads anything. A share is the user picking an app and that
/// app receiving bytes off the phone's own storage, which is what keeps the
/// claim in the README true. See spec-27 dec-10.
class ShareService {
  const ShareService({this.openUrl, this.shareSheet});

  /// The two platform calls, injected so a test can drive this class without
  /// a method channel. Null means use the real one.
  final UrlOpener? openUrl;
  final Sharer? shareSheet;

  /// Sends [message] to [person] and returns the route it actually took.
  ///
  /// WhatsApp not being installed lands in the same place as no number saved:
  /// the share sheet, rather than an error about an app the user never asked
  /// about.
  Future<ShareRoute> sendText(Person person, String message) async {
    final Uri? chat = WhatsAppLink.forPerson(person, message);
    if (chat != null && await _tryOpen(chat)) return ShareRoute.whatsApp;
    await _shareWith(ShareParams(text: message));
    return ShareRoute.shareSheet;
  }

  /// Sends [message] with no particular person in mind, which is how a
  /// shopping list and a stock list go out.
  Future<void> sendBroadcast(String message) =>
      _shareWith(ShareParams(text: message));

  /// Sends a file: a statement PDF, a dues CSV, or a backup.
  ///
  /// [subject] is what an email client uses as its subject line, and [text] is
  /// the covering message where the receiving app takes one.
  Future<void> sendFile(File file, {String? subject, String? text}) =>
      _shareWith(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: subject,
          text: text,
        ),
      );

  Future<bool> _tryOpen(Uri url) async {
    final UrlOpener open = openUrl ?? _openExternally;
    try {
      return await open(url);
    } on Exception {
      // WhatsApp is missing, or the platform refused the intent. Either way
      // the share sheet is the answer, not a message the user cannot act on.
      return false;
    }
  }

  Future<void> _shareWith(ShareParams params) async {
    final Sharer share = shareSheet ?? SharePlus.instance.share;
    await share(params);
  }

  static Future<bool> _openExternally(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
