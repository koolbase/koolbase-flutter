import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Whether the device reports a network connection.
///
/// A hint, not a promise that Koolbase is reachable: requests can still fail
/// while [online]. [unknown] until the platform first answers -- a real state,
/// not a guess: an app should neither show "offline" nor run online-only
/// logic on it.
enum KoolbaseConnectivityState { unknown, online, offline }

/// The device's connectivity, as state an app can render: [state] now,
/// [changes] for every change after.
class KoolbaseConnectivity {
  KoolbaseConnectivity({
    @visibleForTesting Future<List<ConnectivityResult>> Function()? check,
    @visibleForTesting Stream<List<ConnectivityResult>>? changes,
  })  : _check = check,
        _source = changes;

  final Future<List<ConnectivityResult>> Function()? _check;
  final Stream<List<ConnectivityResult>>? _source;
  final StreamController<KoolbaseConnectivityState> _changes =
      StreamController<KoolbaseConnectivityState>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  KoolbaseConnectivityState _state = KoolbaseConnectivityState.unknown;
  // A change event is fresher than the first check: once one arrives, a late
  // answer to that check is ignored.
  bool _heard = false;

  KoolbaseConnectivityState get state => _state;

  /// Every change of [state].
  Stream<KoolbaseConnectivityState> get changes => _changes.stream;

  /// Starts following the platform. Called once by Koolbase.initialize.
  void start() {
    if (_sub != null) return;
    try {
      final source = _source ?? Connectivity().onConnectivityChanged;
      _sub = source.listen((results) {
        _heard = true;
        _set(_from(results));
      }, onError: (Object _) {});
      final check = _check ?? () => Connectivity().checkConnectivity();
      check().then((results) {
        if (!_heard) _set(_from(results));
      }, onError: (Object _) {});
    } catch (_) {
      // No connectivity plugin on this platform: stays unknown.
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _changes.close();
  }

  static KoolbaseConnectivityState _from(List<ConnectivityResult> results) {
    if (results.isEmpty) return KoolbaseConnectivityState.unknown;
    return results.every((r) => r == ConnectivityResult.none)
        ? KoolbaseConnectivityState.offline
        : KoolbaseConnectivityState.online;
  }

  void _set(KoolbaseConnectivityState next) {
    if (next == _state) return;
    _state = next;
    if (!_changes.isClosed) _changes.add(next);
  }
}
