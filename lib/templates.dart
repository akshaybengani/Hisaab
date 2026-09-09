/// The default text a share message starts from.
///
/// These are defaults, not the truth. The user's own wording is stored in
/// `app_settings` under the `SettingKeys.template*` keys and wins wherever it
/// is present, so a template edited on the phone survives an app update. See
/// `StatementTextService`.
///
/// Placeholders are `{name}`, `{items}`, `{total}`, `{paid}`, `{due}` and
/// `{upi}`. Anything else in braces is left in the output exactly as written,
/// because a typo in a template the user typed should read back to them rather
/// than vanish or throw.
///
/// A line whose placeholder resolves to nothing is dropped whole. That is what
/// lets a template carry a UPI line without it reading "UPI" followed by
/// silence on a book where no handle has been saved.
library;

import 'constants.dart';

abstract final class Templates {
  /// The full position, for someone who asked what they owe.
  static const String statement =
      'Hi {name}, here is where things stand.\n'
      '\n'
      '{items}\n'
      '\n'
      'Total {total}\n'
      'Paid {paid}\n'
      'Due {due}\n'
      'UPI {upi}';

  /// A person is doing the book owner a favour by buying through her, so this
  /// is a nudge between neighbours and not a shop chasing an invoice. Short,
  /// warm, and it names one figure.
  static const String reminder =
      'Hi {name}, no rush at all, just so you have it, {due} is still open. '
      'Cash or a transfer, whichever is easier for you.\n'
      '\n'
      'UPI {upi}';

  /// Sent straight after money changes hands, so it leads with the amount and
  /// says what is left.
  static const String receipt =
      'Hi {name}, received {paid}, thank you.\n'
      '\n'
      '{items}\n'
      '\n'
      'Due now {due}';

  /// Everything pending, collapsed to one line per product, which is what
  /// actually gets typed into an order.
  static const String shoppingList =
      'Shopping list\n'
      '\n'
      '{items}\n'
      '\n'
      'Estimated total {total}';

  /// Answers the question that gets asked most often over WhatsApp.
  static const String inStock =
      'In stock right now\n'
      '\n'
      '{items}\n'
      '\n'
      'Value at current prices {total}';

  /// Every template against the settings key it is stored under, so the
  /// settings screen can list them without a second table to keep in step.
  static const Map<String, String> defaults = <String, String>{
    SettingKeys.templateStatement: statement,
    SettingKeys.templateReminder: reminder,
    SettingKeys.templateReceipt: receipt,
    SettingKeys.templateShoppingList: shoppingList,
    SettingKeys.templateInStock: inStock,
  };

  /// A human name for each template, for the settings screen.
  static const Map<String, String> titles = <String, String>{
    SettingKeys.templateStatement: 'Statement',
    SettingKeys.templateReminder: 'Payment reminder',
    SettingKeys.templateReceipt: 'Receipt',
    SettingKeys.templateShoppingList: 'Shopping list',
    SettingKeys.templateInStock: 'What is in stock',
  };

  /// The placeholders a template may use, for the help text under the editor.
  static const List<String> placeholders = <String>[
    '{name}',
    '{items}',
    '{total}',
    '{paid}',
    '{due}',
    '{upi}',
  ];
}
