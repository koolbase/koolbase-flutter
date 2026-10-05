import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/realtime/realtime_client.dart';

/// A stand-in connection: records what is sent; closes on demand.
class _FakeConnection {
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

  List<String> actions(String action) => [
        for (final m in sent)
          if (m['action'] == action) m['collection'] as String,
      ];
}

final _token =
    'h.${base64.encode(utf8.encode(jsonEncode({'project_id': 'p1'})))}.s';
const _grace = Duration(milliseconds: 40);

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<_FakeConnection> opened;

  KoolbaseRealtimeClient client({Future<String?> Function()? tokens}) {
    opened = [];
    return KoolbaseRealtimeClient(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      accessTokenProvider: tokens ?? () async => _token,
      idleGrace: _grace,
      connector: (uri) {
        final f = _FakeConnection();
        opened.add(f);
        return f.connection;
      },
    );
  }

  test('one connection for every listener that arrives while the token is on its way', () async {
    final rt = client();
    final subs = [
      rt.on(collection: 'songs').listen((_) {}),
      rt.on(collection: 'songs').listen((_) {}),
      rt.on(collection: 'albums').listen((_) {}),
    ];
    await _settle();
    expect(opened, hasLength(1));
    expect(opened.single.actions('subscribe')..sort(), ['albums', 'songs']);
    for (final s in subs) {
      await s.cancel();
    }
    rt.dispose();
  });

  test('two listeners on one collection: unsubscribed only when both leave', () async {
    final rt = client();
    final a = rt.on(collection: 'songs').listen((_) {});
    final b = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    await a.cancel();
    await _settle();
    expect(opened.single.actions('unsubscribe'), isEmpty);
    await b.cancel();
    await _settle();
    expect(opened.single.actions('unsubscribe'), ['songs']);
    rt.dispose();
  });

  test('the connection closes a moment after the last listener leaves', () async {
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    await s.cancel();
    await _settle();
    expect(opened.single.closed, isFalse);
    await Future<void>.delayed(_grace * 3);
    expect(opened.single.closed, isTrue);
    expect(opened, hasLength(1));
    rt.dispose();
  });

  test('a listener back within the moment keeps the same connection', () async {
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    await s.cancel();
    final again = rt.on(collection: 'songs').listen((_) {});
    await Future<void>.delayed(_grace * 3);
    expect(opened, hasLength(1));
    expect(opened.single.closed, isFalse);
    expect(opened.single.actions('subscribe'), ['songs', 'songs']);
    await again.cancel();
    rt.dispose();
  });

  test('after the close, a new listener opens a fresh connection', () async {
    final rt = client();
    final s = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    await s.cancel();
    await Future<void>.delayed(_grace * 3);
    final again = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    expect(opened, hasLength(2));
    expect(opened.last.closed, isFalse);
    await again.cancel();
    rt.dispose();
  });

  test('nothing opens when everyone left before the token arrived', () async {
    final gate = Completer<String?>();
    final rt = client(tokens: () => gate.future);
    final s = rt.on(collection: 'songs').listen((_) {});
    await s.cancel();
    gate.complete(_token);
    await _settle();
    expect(opened, isEmpty);
    rt.dispose();
  });

  test('a token that throws does not leave the client stuck', () async {
    var calls = 0;
    final rt = client(tokens: () async {
      calls += 1;
      if (calls == 1) throw StateError('refresh failed');
      return _token;
    });
    final a = rt.on(collection: 'songs').listen((_) {});
    await _settle();
    expect(opened, isEmpty);
    // Stuck "connecting", this listener would open nothing.
    final b = rt.on(collection: 'albums').listen((_) {});
    await _settle();
    expect(opened, hasLength(1));
    await a.cancel();
    await b.cancel();
    rt.dispose();
  });
}
