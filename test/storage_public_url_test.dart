// The project-identity contract for storage public URLs (SDK 11.1.0).
//
// Identity arrives with the bootstrap payload and persists in its cache.
// publicUrlFor throws a TYPED exception while identity is unavailable --
// a different state from a null public URL (known project, private
// bucket) -- and nudges a bootstrap refresh so the session can heal.

import 'package:flutter_test/flutter_test.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

void main() {
  group('KoolbasePayload identity', () {
    test('parses project_id and round-trips through toJson (cache path)', () {
      final p = KoolbasePayload.fromJson(<String, dynamic>{
        'payload_version': 'v1',
        'project_id': 'proj-123',
        'flags': <String, dynamic>{},
        'config': <String, dynamic>{},
        'version': <String, dynamic>{},
      });
      expect(p.projectId, 'proj-123');
      final back = KoolbasePayload.fromJson(p.toJson());
      expect(back.projectId, 'proj-123');
    });

    test('absent project_id parses as empty (older server / older cache)',
        () {
      final p = KoolbasePayload.fromJson(<String, dynamic>{
        'payload_version': 'v1',
        'flags': <String, dynamic>{},
        'config': <String, dynamic>{},
        'version': <String, dynamic>{},
      });
      expect(p.projectId, '');
    });
  });

  group('publicUrlFor', () {
    KoolbaseStorageClient client({String pid = '', void Function()? nudge}) =>
        KoolbaseStorageClient(
          baseUrl: 'https://api.example.com',
          publicKey: 'pk_test_x',
          projectIdProvider: () => pid,
          nudgeBootstrap: nudge,
        );

    test('identity missing: throws typed exception and nudges bootstrap',
        () {
      var nudged = 0;
      final c = client(nudge: () => nudged++);
      expect(
        () => c.publicUrlFor(bucket: 'avatars', path: 'me.png'),
        throwsA(
          isA<KoolbaseStorageProjectIdentityException>().having(
            (e) => e.code,
            'code',
            'project_identity_unavailable',
          ),
        ),
      );
      expect(nudged, 1);
    });

    test('identity present: builds the exact static-publicUrl output', () {
      final c = client(pid: 'proj-123');
      expect(
        c.publicUrlFor(bucket: 'avatars', path: 'users/ke nn/pic#1.png'),
        KoolbaseStorageClient.publicUrl(
          projectId: 'proj-123',
          bucket: 'avatars',
          path: 'users/ke nn/pic#1.png',
        ),
      );
      expect(
        c.publicUrlFor(bucket: 'avatars', path: 'me.png'),
        'https://cdn.koolbase.com/proj-123/avatars/me.png',
      );
    });

    test('transform passes through to the URL', () {
      final c = client(pid: 'proj-123');
      final url = c.publicUrlFor(
        bucket: 'avatars',
        path: 'me.png',
        transform: const KoolbaseImageTransform(width: 100, height: 100),
      );
      expect(url, contains('/cdn-cgi/image/width=100,height=100/'));
    });
  });
}
