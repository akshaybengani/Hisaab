<div align="center">

# Hisaab

**A fully offline ledger for handing out products at cost and collecting the cash back.**

Not an inventory app. It tracks who owes you money, and stock is a by-product.

[![Status](https://img.shields.io/badge/status-designed%2C%20not%20built-B3261E)](#what-exists-today)
[![Platform](https://img.shields.io/badge/platform-Android-1B5E4F)](#running-it)
[![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-1B5E4F)](#running-it)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-1B5E4F)](LICENSE)

</div>

---

## What exists today

Nothing is built. As of 9 Sep 2026 this repository holds this README and nothing else.

The design below is settled and recorded as a spec, with every choice written down alongside the alternative it beat. Each section says plainly whether the thing it describes exists. Nothing here is a feature list of software you can run.

## Why this exists

A friend of mine buys Herbalife products for herself and for people in her local society. The people around her want to pay in cash, so instead of everyone placing a separate order, she orders the lot on her own account, pays online, hands the units out, and collects cash back afterwards. She adds no markup. It isn't a business, it's a favour that outgrew her memory.

What she loses track of is not stock, it's money. Who took how many units, what that came to, how much of it they've paid, and who she still has to ask. The uncomfortable part isn't the arithmetic, it's asking someone for money without being sure of the figure.

Every app I looked at was either a shop billing system with invoices and tax, or a personal expense tracker with no concept of another person owing you. This is the small thing in between.

The name is the question it answers: kiska kitna hisaab baaki hai.

## The idea that makes it work: nothing that matters is stored

The obvious design gives each person a `balance` column and each product a `qty` column, and updates them as things happen. That design is wrong in a way you find out about six weeks later: the columns disagree with the history behind them, and there is no way to tell which one lied.

Hisaab stores events and derives every figure on every read:

```
balance(person)   = Σ (qty × unit_price of their delivery lines)
                  − Σ their money entries

on_hand(product)  = Σ purchased  −  Σ delivered  ±  Σ adjustments
```

A payment is a row. A correction is a row. Her own consumption is a row. There is no counter to fall out of step, and any number on screen can be explained by listing the rows it came from.

Two consequences worth stating, because they are the whole design:

**The unit price is copied onto the delivery line at the moment of the handover.** It is a historical fact, not a lookup. When a product's price rises, every statement already sent still reads the same and still reconciles with the cash already collected. A line that read its price from the product record would silently rewrite her books on every price edit.

**The manual plus and minus buttons write history too.** She asked to be able to correct stock by hand, which invites a mutable counter. Instead each tap appends an adjustment carrying a reason: personal use, recount, damaged, gifted, or manual. The buttons feel identical to use, and `recount` writes whatever delta makes the figure match the count she just did, which is the escape hatch for drift.

Medstock reaches the same conclusion by a different route: it stores a counted snapshot with a date and replays consumption forward, rather than running a nightly job that decrements.

## Cases the design has to get right

Not built. These are the cases the arithmetic is designed against, and the ones its tests will assert.

**A partial payment spanning two handovers.** Priya takes 2 Formula 1 at ₹2,050 each on 3 Sep 2026, then 1 Afresh at ₹950 on 7 Sep, so ₹5,050. She hands over ₹4,500 on 8 Sep, leaving ₹550. The 3 Sep handover shows as paid and the 7 Sep one as partly paid, with ₹400 of ₹950 covered. That allocation is computed on read and never stored, so it cannot disagree with the balance.

**A price rise.** Formula 1 goes to ₹2,150 on 10 Sep. Priya's 3 Sep line still reads ₹2,050 and her total still reads ₹5,050. The next handover uses ₹2,150.

**A household with one payer.** Several people in one house take units and one of them pays. The payer is a single person record, and each handover carries a free-text member name, so the statement reads "2 Formula 1 for Priya" and "1 Afresh for Anil" against one balance. A full grouping model buys nothing here, because there is only ever one payer.

**Her own consumption.** She opens a Formula 1 for herself: stock, minus one, reason personal use. On hand drops by 1, a household expense of ₹2,150 is written, and nobody's balance moves. This is the only place the ledger half and the expense half of the app touch.

**A cash loan next to product dues.** Someone owes ₹950 for an Afresh and separately borrowed ₹5,000 in cash. Their statement shows the two as labelled groups with one net figure underneath, and a payment declares which group it pays. Pooling them would let a product payment quietly pay down a loan, and the statement she sends back would be wrong in a way she'd never spot.

## Sharing a position

Not built. One statement model renders three ways so the figures cannot disagree: templated text to the share sheet, a PDF generated on the device, and a CSV of the dues list.

Templates are editable, because the tone of asking for money as a favour is nothing like a shop's, and only she can word it. Five ship by default: statement, payment reminder, receipt after collecting, consolidated shopping list, and what's in stock now.

## Privacy, and what it costs

Not built. These are commitments the build has to honour, and each is written so you can check it rather than trust it.

The book records what named neighbours owe a private individual. Those people never agreed to be in an app, which is why the posture is as strict as it is.

**No network.** There will be no HTTP client, socket, or WebSocket anywhere in the codebase, and the release APK will declare no `INTERNET` permission. Debug builds do declare it, because that is the Flutter tool's own manifest for hot reload, so the release artifact is the one to inspect. Until there is a build, treat this as a stated intention and not a verified fact.

**No cloud backup.** The database will be excluded from Android cloud backup and device-to-device transfer, so the book is never swept into someone else's infrastructure. The cost is real: there is no automatic restore on a new phone. Export is the mitigation, and it means one device is the book.

**No lock of its own.** There is no account and no app-level passcode, which is the right call for a single-user offline app and worth saying rather than leaving as a gap. Anyone holding the unlocked phone can read the book. The device lock screen is the only thing protecting it.

**Restore replaces, it never merges.** Import will make the file become the book, in a single transaction, after a confirmation that names what will be lost. Merging two books means guessing whether two people are the same person and which balance wins, and a wrong guess there silently changes what someone owes.

## Repository layout

Currently this README, the licence, and a `.gitignore`. The planned shape, none of which exists:

```
lib/
  helpers/
    ledger_math.dart    balances, oldest-first allocation, statement assembly
    stock_math.dart     on hand, movement history, valuation
  models/               product, person, delivery, money entry, adjustment, expense
  services/             database + migrations, backup, pdf, share, settings
  repositories/         one per table
  providers/            app state, theme
  components/           cards, dialogs, the stock stepper
  screens/              dues, people, deliver, requests, stock, purchases, expenses, reports, settings
```

## Running it

There is no app to run. When there is, it will need Flutter 3.44 or newer with Dart 3.12 or newer, and the usual three commands:

```bash
flutter pub get
flutter test
flutter run
```

Distribution is Android sideload. Release signing will read `android/key.properties`, which is deliberately absent from this repository along with the keystore it points at. To set up your own once the project exists:

```bash
keytool -genkeypair -v -keystore android/hisaab-release.jks \
  -alias hisaab -keyalg RSA -keysize 4096 -validity 10950 -storetype PKCS12
```

then create `android/key.properties` with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Back up both files somewhere private. Losing them means you can never update an app already published under that key.

## Tests

None yet. The suites the design owes, and what each has to catch:

| Suite | What it has to catch |
|---|---|
| `ledger_math_test` | The five cases above, oldest-first allocation, partial and lumped payments, negative balances, price snapshot immutability |
| `stock_math_test` | On hand across purchases, deliveries, and each adjustment reason, plus recount deltas |
| `backup_test` | A full export and import round trip, and a truncated file leaving the book untouched |
| `migration_test` | A hand-built v1 database upgraded to current, and `onCreate` against `onUpgrade` |
| `widget_smoke_test` | Every screen in both themes at a 360 by 560 surface, to catch overflow |
| `app_flow_test` | End to end through the real sqflite schema, no mocks |

The last two are not padding. Building Medstock, several genuine bugs were found only by rendering and driving the app rather than by reading it, including a widget that crashed on exactly one card state and a lazy list that unregistered a form field so its validator never ran.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE). Read it, run it, change it, share it for any noncommercial purpose. Commercial use needs written permission.

**Hisaab is not accounting software.** It keeps no tax records, issues no invoice, and gives no financial advice. Every figure in it is one you typed, and nothing in it should be relied on for anything official.
