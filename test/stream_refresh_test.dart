import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/src/database/database_query.dart';

/// A write to a collection now refreshes every open query on it.
///
/// Before this, insert invalidated the cache and stopped there — which only
/// affects the NEXT query. A listener already watching sat unchanged until
/// something happened to re-fetch, so a message sent in a chat thread did not
/// appear in that thread. Nothing errored and nothing logged; the data was
/// simply absent.
///
/// The refresh is a registered CLOSURE per stream rather than something
/// rebuilt from the stream key. A key carries collection, filters, and user —
/// not the ordering, limit, or populated fields — so a query reconstructed
/// from one would run differently and push the wrong records into a stream
/// that never asked for them.
void main() {
  setUp(debugClearStreamRefreshers);

  test('refreshing a collection runs only that collection\'s refreshers',
      () async {
    final ran = <String>[];

    debugRegisterStreamRefresher(
        'messages:{}:u1', () async => ran.add('messages-all'));
    debugRegisterStreamRefresher(
        'messages:{"room_id":"r1"}:u1', () async => ran.add('messages-room1'));
    debugRegisterStreamRefresher('rooms:{}:u1', () async => ran.add('rooms'));

    await refreshCollectionStreams('messages');

    expect(ran, containsAll(['messages-all', 'messages-room1']));
    expect(ran, isNot(contains('rooms')),
        reason:
            'a write to one collection must not refresh queries on another');
  });

  test('a collection with no open streams refreshes nothing', () async {
    var ran = 0;
    debugRegisterStreamRefresher('rooms:{}:u1', () async => ran++);

    await refreshCollectionStreams('messages');

    expect(ran, 0);
  });

  // A prefix match on the collection name must not catch a collection whose
  // name merely starts the same way — "chat" and "chat_rooms" are different
  // collections, and refreshing one because the other was written to would
  // push records into unrelated streams.
  test('collection matching is exact, not a loose prefix', () async {
    final ran = <String>[];

    debugRegisterStreamRefresher('chat:{}:u1', () async => ran.add('chat'));
    debugRegisterStreamRefresher(
        'chat_rooms:{}:u1', () async => ran.add('chat_rooms'));

    await refreshCollectionStreams('chat');

    expect(ran, equals(['chat']),
        reason: 'chat_rooms is a different collection from chat');
  });

  // A refresher that throws must not stop the others: one failing query is
  // not a reason to leave every other listener stale.
  test('a failing refresher does not stop the rest', () async {
    final ran = <String>[];

    debugRegisterStreamRefresher('messages:{"a":1}:u1', () async {
      throw StateError('network down');
    });
    debugRegisterStreamRefresher(
        'messages:{"b":2}:u1', () async => ran.add('second'));

    await refreshCollectionStreams('messages');

    expect(ran, contains('second'));
  });
}
