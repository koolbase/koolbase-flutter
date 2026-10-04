import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/realtime/realtime_client.dart';

/// A stand-in connection: remembers its address and what is sent.
class _FakeConnection {
  _FakeConnection(this.uri);

  final Uri uri;
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  late final RealtimeConnection connection = RealtimeConnection(
    stream: incoming.stream,
    send: (m) => sent.add(jsonDecode(m) as Map<String, dynamic>),
    close: () {
      closed = true;
      incoming.close();
    },
  );
}

final _token =
    'h.${base64.encode(utf8.encode(jsonEncode({'project_id': 'p1'})))}.s';
const _publicUrl = 'wss://api.test/v1/realtime/ws?public_key=pk_test';

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<_FakeConnection> opened;
  String? user;
  String? tok;

  KoolbaseRealtimeClient client({Future<String?> Function()? tokens}) {
    opened = [];
    return KoolbaseRealtimeClient(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      accessTokenProvider: tokens ?? () async => tok,
      userIdProvider: () => user,
      idleGrace: const Duration(milliseconds: 40),
      connector: (uri) {
        final f = _FakeConnection(uri);
        opened.add(f);
        return f.connection;
      },
    );
  }

  setUp(() {
    user = null;
    tok = null;
  });

  test(
      'signed out: connects with the public key; subscribes without a project id',
      () async {
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    expect(opened, hasLength(1));
    expect(opened.single.uri.toString(), _publicUrl);
    expect(opened.single.sent, [
      {'action': 'subscribe', 'collection': 'songs'},
    ]);
    await s.cancel();
    await _settle();
    expect(opened.single.sent.last,
        {'action': 'unsubscribe', 'collection': 'songs'});
    rt.dispose();
  });

  test('signed out: events still reach the listener', () async {
    final rt = client();
    final got = <String?>[];
    final s = rt.on(collection: 'songs').listen((e) => got.add(e.recordId));
    await _settle();
    opened.single.incoming.add(jsonEncode({
      'type': 'db.record.deleted',
      'payload': {'collection': 'songs', 'record_id': 'r1'},
    }));
    await _settle();
    expect(got, ['r1']);
    await s.cancel();
    rt.dispose();
  });

  test('signed in with no usable token: opens nothing, never public-only',
      () async {
    user = 'u1';
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    expect(opened, isEmpty);
    await s.cancel();
    rt.dispose();
  });

  test('a token that throws: opens nothing, never public-only', () async {
    final rt = client(tokens: () async {
      throw StateError('refresh failed');
    });
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    expect(opened, isEmpty);
    await s.cancel();
    rt.dispose();
  });

  test('sign-in replaces the signed-out connection and resubscribes everything',
      () async {
    final rt = client();
    final a = rt.on(collection: 'songs').listen((_) {});
    final b = rt.on(collection: 'albums').listen((_) {});
    await _settle();
    final anon = opened.single;

    user = 'u1';
    tok = _token;
    rt.sessionChanged();
    expect(anon.closed, isTrue);
    await _settle();
    expect(opened, hasLength(2));
    expect(opened.last.uri.toString(), contains('/v1/realtime/ws?token='));
    expect(opened.last.sent, [
      {'action': 'subscribe', 'project_id': 'p1', 'collection': 'songs'},
      {'action': 'subscribe', 'project_id': 'p1', 'collection': 'albums'},
    ]);
    await a.cancel();
    await b.cancel();
    rt.dispose();
  });

  test('sign-out replaces the signed-in connection with a public-key one',
      () async {
    user = 'u1';
    tok = _token;
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    final signedIn = opened.single;

    user = null;
    tok = null;
    rt.sessionChanged();
    expect(signedIn.closed, isTrue);
    await _settle();
    expect(opened, hasLength(2));
    expect(opened.last.uri.toString(), _publicUrl);
    expect(opened.last.sent, [
      {'action': 'subscribe', 'collection': 'songs'},
    ]);
    await s.cancel();
    rt.dispose();
  });

  test('the same user again (a token refresh) keeps the connection', () async {
    user = 'u1';
    tok = _token;
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    rt.sessionChanged();
    await _settle();
    expect(opened, hasLength(1));
    expect(opened.single.closed, isFalse);
    await s.cancel();
    rt.dispose();
  });

  test('still signed out keeps the signed-out connection', () async {
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    rt.sessionChanged();
    await _settle();
    expect(opened, hasLength(1));
    expect(opened.single.closed, isFalse);
    await s.cancel();
    rt.dispose();
  });

  test('with nothing open, a session change opens nothing', () async {
    final rt = client();
    user = 'u1';
    tok = _token;
    rt.sessionChanged();
    await _settle();
    expect(opened, isEmpty);
    rt.dispose();
  });

  test(
      'a session change while the token is on its way: one connection, for the new session',
      () async {
    var calls = 0;
    final gate = Completer<String?>();
    final rt = client(tokens: () {
      calls += 1;
      return calls == 1 ? gate.future : Future<String?>.value(_token);
    });
    final s = rt.on(collection: 'songs').listen((_) {});
    user = 'u1';
    rt.sessionChanged();
    await _settle();
    gate.complete(null); // the old, signed-out answer arrives late
    await _settle();
    expect(opened, hasLength(1));
    expect(opened.single.uri.toString(), contains('?token='));
    await s.cancel();
    rt.dispose();
  });
}
