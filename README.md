<div align="center">

<img src="assets/branding/icon.png" width="104" alt="Hisaab" />

# Hisaab

**A fully offline ledger for handing out things at cost and collecting the cash back.**

Not an inventory app. It tracks who owes you money, and stock is a by-product.

[![Platform](https://img.shields.io/badge/platform-Android%2010%2B-333196)](#running-it)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-333196)](#running-it)
[![Tests](https://img.shields.io/badge/tests-342%20%2B%208%20on%20device-333196)](#tests)
[![Network](https://img.shields.io/badge/network-none-333196)](#privacy-and-what-it-costs)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-333196)](LICENSE)

</div>

---

## Why this exists

A friend of mine buys health products for herself and for people in her local society. They want to pay in cash, so instead of everyone placing a separate order, she orders the lot on her own account, pays online, hands the units out, and collects cash back afterwards. She adds no markup. It isn't a business, it's a favour that outgrew her memory.

What she loses track of is not stock, it's money. Who took how many units, what that came to, how much of it they've paid, and who she still has to ask. The uncomfortable part isn't the arithmetic, it's asking someone for money without being sure of the figure.

Every app I looked at was either a shop billing system with invoices and tax, or a personal expense tracker with no concept of another person owing you. This is the small thing in between. It ships with an empty catalogue and no assumptions, so it works for anything you buy in bulk and pass on at cost.

The name is the question it answers: kiska kitna hisaab baaki hai.

## The idea that makes it work: nothing that matters is stored

The obvious design gives each person a `balance` column and each product a `qty` column, and updates them as things happen. That design is wrong in a way you find out about six weeks later: the columns disagree with the history behind them, and there is no way to tell which one lied.

Hisaab stores events and derives every figure on every read:

```
balance(person)   = Σ (qty × unit_price of their delivery lines)
                  − Σ their money entries

on_hand(product)  = Σ purchased  −  Σ delivered  ±  Σ adjustments
```

A payment is a row. A correction is a row. Your own consumption is a row. There is no counter to fall out of step, and any number on screen can be explained by listing the rows behind it. A test asserts that no table in the schema carries a balance or a quantity column, so this cannot quietly stop being true.

Three consequences worth stating, because they are the whole design:

**The unit price is copied onto the delivery line at the moment of the handover.** It is a historical fact, not a lookup. When a product's price rises, every statement already sent still reads the same and still reconciles with the cash already collected. `DeliveryItem.snapshot` is the only way to build a line, so this is a property of the type rather than something each screen has to remember.

**The manual plus and minus buttons write history too.** Each tap appends an adjustment carrying a reason: personal use, recount, damaged, gifted, or manual. The buttons feel ordinary to use, and `recount` writes whatever delta makes the figure match the count you just did, which is the escape hatch for drift.

**Payments are allocated oldest first, on read, and never stored.** That is what lets one note settle three handovers while each one still shows as paid, settled, partly paid, or unpaid.

## Cases the design gets right

These are the situations the arithmetic is built around, and each one is a test.

**A partial payment spanning two handovers.** Priya takes 2 tubs at ₹2,050 each on 3 Sep 2026, then 1 jar at ₹950 on 7 Sep, so ₹5,050. She hands over ₹4,500 on 8 Sep, leaving ₹550. The 3 Sep handover shows as paid and the 7 Sep one as partly paid, with ₹400 of ₹950 covered.

**A price rise.** The tub goes to ₹2,150 on 10 Sep. Priya's 3 Sep line still reads ₹2,050 and her total still reads ₹5,050. The next handover uses ₹2,150.

**A household with one payer.** Several people in one house take units and one of them pays. The payer is a single person record, and each handover carries a free-text member name, so the statement reads "2 tubs for Priya" and "1 jar for Anil" against one balance. A full grouping model buys nothing here, because there is only ever one payer.

**Cash is physical, so a balance rarely lands round.** Someone owing ₹950 hands you ₹900 and you close it: that is a **discount given**. They hand you ₹1,000 and you keep the difference: that is **change kept**. Neither happens automatically, both are recorded as their own entry rather than by quietly altering the payment, and the delivery then reads **settled** rather than **paid**, naming the amount conceded. The recorded payment always equals the cash that actually moved.

**Your own consumption.** Open a tub for yourself: stock, minus one, reason personal use. On hand drops by 1, a household expense is written at the current price, and nobody's balance moves. This is the only place the ledger half and the expense half of the app touch.

**A cash loan next to product dues.** Someone owes ₹950 for a jar and separately borrowed ₹5,000 in cash. Their statement shows the two as labelled groups with one net figure, and a payment declares which group it pays. Pooling them would let a product payment quietly pay down a loan, and the statement you send back would be wrong in a way you'd never spot.

**A purchase that didn't cost what its lines say.** Paying ₹200 more than the lines is shipping you absorbed, and the app offers to log it as an expense. Paying ₹50 less is a **discount received**, which is a saving, so it is named and never offered as an expense.

## Sharing

One statement model renders three ways, so the figures cannot disagree between them: templated text to the share sheet, a PDF generated on the device, and a CSV of the dues list.

Templates are editable, because the tone of asking for money as a favour is nothing like a shop's, and only you can word it. Five ship by default: statement, payment reminder, receipt, consolidated shopping list, and what's in stock now. Placeholders that don't resolve are left in the text literally rather than vanishing, so a typo reads back to you.

The PDF bundles Noto Sans. This isn't decoration: the built-in PDF fonts are Latin-1 only, so every ₹ would render as a blank box in the one document you actually hand to someone. It also carries a header and footer you set in settings, so nothing personal is baked into the build.

Where a person has a phone number saved, sharing opens their WhatsApp chat through a `wa.me` link. Without one, the system share sheet handles it.

## Privacy, and what it costs

The book records what named neighbours owe a private individual. Those people never agreed to be in an app, which is why the posture is as strict as it is. Each claim below is written so you can check it rather than trust it.

**No network.** There is no HTTP client, socket, or WebSocket anywhere in `lib/`, and the release APK declares **no permissions at all**, not even `INTERNET`. Debug builds do declare it, because that is the Flutter tool's own manifest for hot reload, so the release artifact is the one to inspect. Two things enforce this rather than document it: `test/offline_posture_test.dart` scans the source, and `tool/verify_offline.sh` reads the merged release manifest, which is the only place the claim is actually true or false.

```bash
flutter build apk --release
tool/verify_offline.sh
```

**No cloud backup.** The database is excluded from Android cloud backup and from device-to-device transfer, both declared in `android/app/src/main/res/xml/data_extraction_rules.xml`. The cost is real: **there is no automatic restore on a new phone.** Export is the mitigation, and it means one device is the book. Losing the phone without an export loses the ledger.

**No lock of its own.** There is no account and no app passcode. Anyone holding the unlocked phone can read the book. The device lock screen is the only thing protecting it, and that is a deliberate choice for a single-user offline app rather than an oversight.

**Restore replaces, it never merges.** Import validates the whole file first, names the counts you are about to lose, then replaces the book in a single transaction. A malformed file changes nothing. Merging two books would mean guessing whether two people are the same person and which balance wins, and a wrong guess there silently changes what someone owes.

## Repository layout

```
lib/
  constants.dart          money kinds, stock reasons, request lifecycle, settlement states
  helpers/
    ledger_math.dart      balances, oldest-first allocation, statement assembly
    stock_math.dart       on hand, movement history, shopping list
    money.dart            paise in, grouped rupees out
    dates.dart            day-only arithmetic and one date format
  models/                 14 tables' worth of plain data, plus the derived Statement
  services/
    database_service.dart schema and ordered migrations
    backup_service.dart   JSON export, validated replace-all import
    statement_*_service   text, PDF and CSV over one Statement
    share_service.dart    wa.me links and the share sheet
  repositories/           one per table, behind interfaces
  providers/              app state, held in memory, reloaded after each write
  components/             the presentational half of every screen
  screens/                dues, people, deliver, collect, requests, stock, purchases,
                          expenses, categories, products, settings
tool/verify_offline.sh    checks the privacy claim against the built APK
```

Money is an `int` count of paise everywhere. There is no floating point anywhere near a balance.

State is `provider` with `ChangeNotifier`. The dataset is one person's social circle, so tens of people and low hundreds of rows, which is small enough to hold in memory and reload after each write. That keeps every derived figure consistent with no caching layer.

## Running it

Requires Flutter 3.44 or newer with Dart 3.12 or newer, and an Android 10 device or emulator.

```bash
flutter pub get
flutter test
flutter run
```

The full app can be driven end to end on a device:

```bash
flutter test integration_test/app_test.dart -d <device-id>
```

Release builds, split per architecture because one fat APK is roughly twice the size:

```bash
flutter build apk --release --split-per-abi
```

That produces about 20 MB for arm64, which is what a modern phone needs. Most of it is the PDF renderer and its bundled font.

### Signing

Release signing reads `android/key.properties`, which is **not** in this repository, along with the keystore it points at. Without it the release build falls back to debug keys and prints a warning, which is fine for testing and never for anything someone will install and expect to update. To make your own:

```bash
keytool -genkeypair -v -keystore android/hisaab-release.jks \
  -alias hisaab -keyalg RSA -keysize 4096 -validity 10950 -storetype PKCS12
```

Then create `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. Back up both files somewhere private. Losing them means you can never update an app already installed under that key.

## Tests

```
flutter analyze   # clean
flutter test      # 342 tests
```

| Suite | Tests | What it covers |
|---|---|---|
| `screens_render_test` | 102 | Every screen with data and empty, at 360 by 560, in both themes |
| `ledger_math_test` | 56 | Balances, oldest-first allocation, the two pools, settlement states |
| `repository_test` | 43 | Every repository, transactions, archiving, the request lifecycle |
| `statement_render_test` | 26 | Text, PDF and CSV agreeing, templates, CSV quoting, `wa.me` links |
| `backup_test` | 25 | Export and import round trips, and files that cannot be trusted |
| `stock_math_test` | 24 | On hand, recount deltas, movement history, the shopping list |
| `migration_test` | 14 | A hand-built v1 database upgraded and checked row by row |
| `behaviour_test` | 13 | What each screen does when you use it |
| `invariants_test` | 11 | The side effects that must **not** happen |
| `collect_test` | 10 | Discounts, change, and which pool a payment settles |
| `empty_states_test` | 9 | Every list surface names a next action |
| `copy_rules_test` | 4 | House style, including the no-dash rule |
| `offline_posture_test` | 3 | No networking imports, and the manifest |
| `widget_test` | 2 | The app boots |

Plus 8 integration tests driving the real app against the real database on a device.

What the testing actually caught, which is the only interesting part:

- The **360 by 560 render suite** found a request bar that overflowed by 93 pixels once a count sat beside two buttons, and a list that trusted its caller to sort.
- The **integration suite** found that the export tile was dead. `BackupService` was complete with 25 passing tests, and nothing wired it to the settings screen. Since the book is excluded from cloud backup on purpose, export is the only way it survives a new phone, so this was a data-loss bug sitting behind a green suite. Every piece worked; nobody had joined them up.
- A **drift guard** caught the same vocabulary rule being implemented in two places, which broke the moment one of them changed.
- The **invariants suite** exists because several acceptance criteria had a second half nothing checked: "and updates no other table", "and moves no balance", "never written automatically". That is where a regression hides, because the happy path keeps passing.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE). Read it, run it, change it, share it for any noncommercial purpose. Commercial use needs written permission.

**Hisaab is not accounting software.** It keeps no tax records, issues no invoice, and gives no financial advice. Every figure in it is one you typed, and nothing in it should be relied on for anything official.
