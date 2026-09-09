# Hisaab

An offline Android ledger for a friend who buys Herbalife products at cost, hands them
out in her local society, and collects cash back. The problem is money, not stock.

Full design: `akshay/personal/specs/spec-27` in Memex, phase **specify**. It holds 12
resolved decisions with the alternatives they beat. Read it before changing the data
model. The README carries the stranger-facing version.

## Hard rules

**No CI, ever.** No GitHub Actions, no workflow files, no scheduled jobs, no bots. Akshay
has limited credits and every pipeline run spends them. Tests and analysis run locally
only. If a task seems to want automation, ask first.

**Claude is in charge of this project.** Decide the work split, the worktree layout, and
the merge order without asking. Bring decisions to Akshay, not options, unless the choice
is genuinely his (money, scope, what his friend wants).

**Batch every question.** Never stop work to ask one thing. Collect questions and put them
at the end of a message as a numbered plain-language list, then keep going on whatever
isn't blocked. Long uninterrupted sessions beat correct-but-chatty ones.

**Short messages.** Plain language, no filler, no restating what was just done. Say what
changed and what needs an answer.

**The README documents only what exists** per `std-35` cl-14. It currently describes a
working app, so anything added there must actually work, and anything removed from the app
must leave it. Report test counts from a real run, never from memory.

## Handoff protocol

When Akshay says the context is nearly full, or asks for a handoff, produce two things:

1. `HANDOFF.md` at the repo root, overwritten each time. It carries: what changed this
   session, the current branch and worktree state, what is half-done and exactly where,
   open questions still unanswered, and the next three concrete steps.
2. A paste-ready prompt in the chat, short, that points a fresh session at `HANDOFF.md`
   and `spec-27` and names the immediate next action.

`HANDOFF.md` is the entry point for any new session. Read it first, before the README.

## Worktrees and subagents

`main` is the integration branch and only Claude merges into it. Subagents never merge and
never touch `main`.

```
~/Personal/Hisaab                  main, integration, all merges happen here
~/Personal/Hisaab-wt/<lane>        one worktree per lane, branch lane/<name>
```

Rules that keep parallel work from colliding:

- **Contracts land on main first.** Model class shapes and repository interfaces are
  committed to `main` before any lane starts. Lanes code against them, never redefine them.
- **One lane owns a directory.** No two lanes may edit the same file. If a lane needs a
  change outside its directory, it stops and reports rather than reaching across.
- **Schema has a single owner.** Only the data lane writes migrations. A schema change
  mid-flight means pausing the other lanes and re-basing them after it merges.
- **Three lanes maximum.** Flutter builds are heavy and this is one Mac.
- **A lane is mergeable only when** `flutter analyze` is clean and its own tests pass. The
  lane reports both outputs; Claude verifies before merging.
- **Claude merges sequentially**, runs the full suite after each merge, and fixes conflicts
  directly. A broken `main` is fixed before the next merge starts.
- Worktrees are removed once merged. Never leave a stale lane.

The phase 1 split, once contracts are on main:

| Lane | Owns | Depends on |
|---|---|---|
`lane/math` | `lib/helpers/` pure functions and their tests | contracts only, no I/O
`lane/data` | `lib/services/database_service.dart`, migrations, `lib/repositories/` | contracts
`lane/ui` | `lib/screens/`, `lib/components/` against a fake repository | contracts

`lane/math` is the one that must be right, so it gets reviewed hardest.

## Standards that bite here

From `akshay/personal`, cited as `[per std-N]`:

- `std-24` no dash inside prose of any kind, sentence case, numerals with comma-grouped
  thousands, dates as "9 Sep 2026". This catches agent-written copy more than anything else.
- `std-23` anti-slop, every word earns its place.
- `std-35` public README shape, and prove privacy claims rather than asserting them.
- `std-19` hand-authored, sequentially numbered migrations, committed with the ledger.
- `std-13` pin the toolchain, reach it through its version manager. `flutter --version` has
  lied on this Mac before, so verify against the resolved SDK before pinning anything.
- `std-3` resolve decisions before creating tasks. In Memex, tasks exist only in `build`.

## Design tokens

Taken from the app icon. These are the source of truth, no literal colours in widgets
`[per std-27]`.

| Token | Hex |
|---|---|
| primary | `#333196` |
| on primary | `#FFFFFF` |
| secondary | `#B9BAF7` |

Material 3, stock widgets, light and dark and match device, defaulting to the system
setting. Branding assets live in `assets/branding/`, with the original AI output kept at
`design/logo-source.png`. The shipped icon is flattened to exactly the three colours above.

## Stack

Flutter with Material 3, sqflite, provider with ChangeNotifier, pdf and printing for
on-device statements, share_plus and url_launcher for the share sheet and `wa.me` links,
file_picker for import, shared_preferences for settings. Everything offline. Android
sideload only, no Play Store, no iOS.

Package id `com.akshaybengani.hisaab`, minSdk 29 for Android 10. Release signing reads
`android/key.properties`, which stays out of the repository.

## Verifying, not asserting

`tool/verify_offline.sh` checks the privacy claim against the merged release manifest,
because that is the only place the claim is true or false. Run it after any dependency
change: a package that merges in an INTERNET permission would silently make the README
lie. `test/offline_posture_test.dart` covers the source side.

Known debt: the release APK is 43 MB, mostly `printing` and `pdf`. `--split-per-abi`
cuts it to roughly a third and should happen before anything is handed to a real phone.
