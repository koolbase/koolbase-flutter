// The profile photo as one of the user's files: the server's
// {"bucket", "path"} on the user, kept with the persisted session, and set
// by updateProfile(avatar:) after an upload -- or removed.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';
import 'package:koolbase_flutter/src/auth/auth_api.dart';

Map<String, dynamic> _user({Object? avatar}) => {
  'id': 'u1',
  'project_id': 'p1',
  'email': 'maya@example.com',
  'avatar_url': 'https://cdn.test/p1/avatars/maya/me.jpg',
  'verified': true,
  'disabled': false,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
  if (avatar != null) 'avatar': avatar,
};

void main() {
  test("read from the server's user; kept through toJson and copyWith", () {
    final u = KoolbaseUser.fromJson(_user(avatar: {'bucket': 'avatars', 'path': 'maya/me.jpg'}));
    expect(u.avatar, const KoolbaseAvatarFile(bucket: 'avatars', path: 'maya/me.jpg'));
    expect(KoolbaseUser.fromJson(u.toJson()).avatar, u.avatar);
    expect(u.copyWith(fullName: 'Maya').avatar, u.avatar);
  });

  test('none, or not one: null, and nothing written for it', () {
    expect(KoolbaseUser.fromJson(_user()).avatar, isNull);
    expect(KoolbaseUser.fromJson(_user()).toJson().containsKey('avatar'), isFalse);
    expect(KoolbaseUser.fromJson(_user(avatar: {'bucket': 'avatars'})).avatar, isNull);
    expect(KoolbaseUser.fromJson(_user(avatar: 'maya/me.jpg')).avatar, isNull);
  });

  group('updateProfile', () {
    late Map<String, dynamic> sent;
    AuthApi api() => AuthApi(
      baseUrl: 'https://api.test',
      publicKey: 'pk_test',
      client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_user(avatar: sent['avatar'])), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    test('a file: its bucket and path', () async {
      final u = await api().updateProfile(
        accessToken: 't',
        avatar: const KoolbaseAvatarFile(bucket: 'avatars', path: 'maya/me.jpg'),
      );
      expect(sent, {'avatar': {'bucket': 'avatars', 'path': 'maya/me.jpg'}});
      expect(u.avatar?.path, 'maya/me.jpg');
    });

    test('removed: an empty avatar', () async {
      await api().updateProfile(accessToken: 't', removeAvatar: true);
      expect(sent, {'avatar': <String, dynamic>{}});
    });

    test('a name alone sends no photo', () async {
      await api().updateProfile(accessToken: 't', fullName: 'Maya');
      expect(sent, {'full_name': 'Maya'});
    });

    test('two photos at once: refused before anything is sent', () async {
      await expectLater(
        () => api().updateProfile(
          accessToken: 't',
          avatarUrl: 'https://x.test/a.png',
          avatar: const KoolbaseAvatarFile(bucket: 'avatars', path: 'maya/me.jpg'),
        ),
        throwsArgumentError,
      );
    });
  });
}
