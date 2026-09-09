/// Reports test results to Memex, so an acceptance criterion on spec-27 shows
/// as verified by a test that actually ran rather than by someone saying so.
///
/// Memex ships an official helper for JavaScript only, so this is the
/// hand-rolled port of the emission protocol. Re-check whether a Dart helper
/// exists before extending this file: the moment one ships, this stops being
/// ours to maintain.
///
/// It lives under `test/` and is never imported from `lib/`, which is what
/// keeps the app's no-network claim intact. `test/offline_posture_test.dart`
/// enforces that boundary.
///
/// Emission is telemetry and must never fail a test run. Every request is
/// bounded and every error is swallowed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

const String _specRef = 'akshay/personal/specs/spec-27';

/// Expands a bare handle like `ac-8` into the canonical ref the protocol
/// wants. The namespace prefix is what routes the event, so it is never
/// hardcoded to a host.
String ac(String handle) => '$_specRef/acs/$handle';

const Map<String, String> _namespaceToBase = <String, String>{
  'mindset-int': 'https://int.memex.ai',
  'mindset-prod': 'https://memex.ai',
};

/// Anything not in the table is a SaaS tenant, which the namespace selects on
/// the shared host. Never localhost: an event routed there is silently lost
/// while the board still reads unverified.
const String _saasBase = 'https://memex.ai';

const Duration _timeout = Duration(seconds: 5);
const int _maxBatch = 500;
const int _fallbackConcurrency = 4;
const Duration _fallbackDeadline = Duration(seconds: 4);

class _Event {
  _Event({
    required this.acUid,
    required this.status,
    required this.testIdentifier,
    required this.durationMs,
  });

  final String acUid;
  final String status;
  final String testIdentifier;
  final int durationMs;

  String get namespace {
    final int slash = acUid.indexOf('/');
    return slash <= 0 ? '' : acUid.substring(0, slash);
  }

  Map<String, Object?> toPayload() {
    final String? actor = _actor();
    return <String, Object?>{
      'ac_uid': acUid,
      'status': status,
      'test_identifier': testIdentifier,
      'duration_ms': durationMs,
      'actor': ?actor,
      'metadata': <String, String>{'host': 'local'},
    };
  }
}

final List<_Event> _buffer = <_Event>[];
String? _currentFile;

String? _actor() {
  for (final String name in <String>[
    'GITHUB_ACTOR',
    'GITLAB_USER_LOGIN',
    'BUILDKITE_BUILD_AUTHOR',
    'CIRCLE_USERNAME',
    'USER',
    'USERNAME',
  ]) {
    final String? value = Platform.environment[name];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

bool _emissionOff() {
  final String value = (Platform.environment['MEMEX_EMIT'] ?? '').toLowerCase();
  return value == 'false' || value == '0' || value == 'no' || value == 'off';
}

String _baseFor(String namespace) {
  final String? override = Platform.environment['MEMEX_TEST_EVENTS_URL'];
  if (override != null && override.isNotEmpty) return override;
  return _namespaceToBase[namespace] ?? _saasBase;
}

void _warn(String message) => stderr.writeln('ac-emit: $message');

class _Response {
  const _Response(this.status, this.body, this.warning);
  final int status;
  final String body;
  final String? warning;

  bool get ok => status >= 200 && status < 300;
}

Future<_Response> _post(Uri uri, Object body) async {
  final HttpClient client = HttpClient()..connectionTimeout = _timeout;
  try {
    final HttpClientRequest request = await client
        .postUrl(uri)
        .timeout(_timeout);
    request.headers.contentType = ContentType.json;
    final String? key = Platform.environment['MEMEX_EMIT_KEY'];
    if (key != null && key.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
    request.write(jsonEncode(body));
    final HttpClientResponse response = await request.close().timeout(_timeout);
    final String text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
    return _Response(
      response.statusCode,
      text,
      response.headers.value('x-memex-warning'),
    );
  } finally {
    client.close(force: true);
  }
}

/// One POST per event, used only where the batch route is absent. Bounded in
/// both concurrency and total time, because unbounded fan-out is the exact
/// failure the batch endpoint exists to prevent.
Future<void> _fallback(List<_Event> events, String base) async {
  final Uri uri = Uri.parse('$base/api/test-events');
  final DateTime deadline = DateTime.now().add(_fallbackDeadline);
  int dropped = 0;

  for (int i = 0; i < events.length; i += _fallbackConcurrency) {
    if (DateTime.now().isAfter(deadline)) {
      dropped = events.length - i;
      break;
    }
    final Iterable<_Event> slice = events.skip(i).take(_fallbackConcurrency);
    await Future.wait(
      slice.map((_Event e) async {
        try {
          final _Response res = await _post(uri, e.toPayload());
          if (!res.ok) _warn('POST $uri -> ${res.status}: ${res.body}');
        } catch (error) {
          _warn('POST failed: $error');
        }
      }),
    );
  }
  if (dropped > 0) {
    _warn(
      'dropped $dropped event(s): the single-event fallback ran out of time',
    );
  }
}

Future<void> _flush() async {
  if (_buffer.isEmpty) return;
  final List<_Event> events = List<_Event>.of(_buffer);
  _buffer.clear();
  if (_emissionOff()) return;

  final Map<String, List<_Event>> byBase = <String, List<_Event>>{};
  for (final _Event event in events) {
    if (event.namespace.isEmpty) continue;
    byBase.putIfAbsent(_baseFor(event.namespace), () => <_Event>[]).add(event);
  }

  for (final MapEntry<String, List<_Event>> entry in byBase.entries) {
    final Uri uri = Uri.parse('${entry.key}/api/test-events/batch');
    for (int i = 0; i < entry.value.length; i += _maxBatch) {
      final List<_Event> chunk = entry.value.skip(i).take(_maxBatch).toList();
      try {
        final _Response res = await _post(uri, <String, Object?>{
          'events': chunk.map((_Event e) => e.toPayload()).toList(),
        });

        if (res.status == 404 || res.status == 405) {
          // The server predates the batch route, so land the events one by one.
          await _fallback(chunk, entry.key);
          continue;
        }
        if (res.status == 401) {
          // Definitive for this key against this server, so stop rather than
          // sending requests that cannot succeed. Provision a fresh key.
          _warn('401, stopping: ${res.body}');
          return;
        }
        if (!res.ok) {
          // Never retried. A 429 in particular means the server is shedding
          // load, and retrying would multiply requests at the worst moment.
          _warn('batch -> ${res.status}: ${res.body}');
          continue;
        }
        if (res.warning != null) _warn(res.warning!);

        final Object? decoded = jsonDecode(res.body);
        if (decoded is Map<String, Object?> && decoded['rejected'] is int) {
          final int rejected = decoded['rejected']! as int;
          if (rejected > 0) {
            _warn('server rejected $rejected event(s): ${res.body}');
          }
        }
      } catch (error) {
        _warn('batch failed: $error');
      }
    }
  }
}

/// Call once at the top of a test file's `main()`, passing the file's path.
/// Registers the flush that sends this file's events as one request.
void useAcEmission(String testFile) {
  _currentFile = testFile;
  tearDownAll(_flush);
}

/// Runs a test body and buffers one event per acceptance criterion.
///
/// Emits on pass, on failure, and on error, because the board shows the latest
/// result per test and a skipped failure would leave stale green.
Future<void> _tagged(
  String description,
  List<String> acs,
  FutureOr<void> Function() body,
) async {
  final Stopwatch watch = Stopwatch()..start();
  String status = 'pass';
  try {
    await body();
  } on TestFailure {
    status = 'fail';
    rethrow;
  } catch (_) {
    status = 'error';
    rethrow;
  } finally {
    watch.stop();
    final String file = _currentFile ?? 'test';
    for (final String handle in acs) {
      _buffer.add(
        _Event(
          acUid: ac(handle),
          status: status,
          testIdentifier: '$file::$description',
          durationMs: watch.elapsedMilliseconds,
        ),
      );
    }
  }
}

/// Declares a test and the acceptance criteria it verifies.
@isTest
void acTest(
  String description,
  List<String> acs,
  FutureOr<void> Function() body, {
  dynamic skip,
  Timeout? timeout,
}) {
  test(
    description,
    () => _tagged(description, acs, body),
    skip: skip,
    timeout: timeout,
  );
}

/// The widget twin of [acTest], for a criterion whose claim is about what
/// reaches the screen. A pure assertion on the label string would only prove
/// the constant exists, so those criteria get a real render.
@isTest
void acTestWidgets(
  String description,
  List<String> acs,
  WidgetTesterCallback body, {
  bool? skip,
  Timeout? timeout,
}) {
  testWidgets(
    description,
    (WidgetTester tester) => _tagged(description, acs, () => body(tester)),
    skip: skip,
    timeout: timeout,
  );
}
