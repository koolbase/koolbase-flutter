import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_client.dart';
import '../koolbase.dart';

/// The auth states a running app can be in, as the gate models them.
enum KoolbaseAuthStatus {
  /// [KoolbaseAuthClient.restoreSession] is in flight. Shown once, at mount.
  restoring,

  /// A user is signed in. Includes the optimistic offline restore
  /// ([RestoreResult.offline]): the user is populated but API calls may fail
  /// until network returns — [KoolbaseAuthScope.restoredOffline] tells you.
  signedIn,

  /// No user: never signed in, logged out, or the persisted session expired.
  signedOut,
}

/// Branches the widget tree on authentication state, correctly.
///
/// Owns the behavior every app hand-writes and most get subtly wrong:
///
///  * Calls [KoolbaseAuthClient.restoreSession] once at mount, showing
///    [restoring] while it runs — so returning users never see a login
///    screen flash before their session resolves.
///  * Seeds synchronously from [KoolbaseAuthClient.currentUser] and then
///    listens to [KoolbaseAuthClient.authStateChanges]. The seed is not an
///    optimization: the auth stream is a plain broadcast with no replay, so
///    a subscriber that only listens can wait forever for a state it missed.
///  * Maps [RestoreResult.offline] to signed-IN (the SDK restores the
///    session optimistically and populates the user), exposing
///    [KoolbaseAuthScope.restoredOffline] for apps that want a banner.
///  * Cancels its subscription on dispose.
///
/// Appearance is entirely yours — the gate is headless with slots:
///
/// ```dart
/// KoolbaseAuthGate(
///   signedIn: (context, user) => HomeScreen(user: user),
///   signedOut: (context) => const LoginScreen(),
///   // restoring: optional — defaults to a bare centered spinner.
/// )
/// ```
///
/// Descendants read the current user without touching statics, and rebuild
/// when it changes:
///
/// ```dart
/// final user = KoolbaseAuthScope.of(context).user;
/// ```
class KoolbaseAuthGate extends StatefulWidget {
  const KoolbaseAuthGate({
    super.key,
    required this.signedIn,
    required this.signedOut,
    this.restoring,
    @visibleForTesting this.auth,
  });

  /// Test seam only: the auth client to drive instead of [Koolbase.auth].
  /// Production callers never pass this — the gate reads the singleton.
  final KoolbaseAuthClient? auth;

  /// Built when a user is signed in. Receives the current [KoolbaseUser].
  final Widget Function(BuildContext context, KoolbaseUser user) signedIn;

  /// Built when no user is signed in (never signed in, logged out, or the
  /// persisted session expired).
  final Widget Function(BuildContext context) signedOut;

  /// Built while the persisted session is being restored at mount.
  ///
  /// Optional. The default is a bare centered [CircularProgressIndicator] —
  /// deliberately NOT the [signedOut] builder, because flashing a login
  /// screen at a returning user is the exact bug this gate exists to kill.
  final Widget Function(BuildContext context)? restoring;

  @override
  State<KoolbaseAuthGate> createState() => _KoolbaseAuthGateState();
}

class _KoolbaseAuthGateState extends State<KoolbaseAuthGate> {
  KoolbaseAuthClient get _auth => widget.auth ?? Koolbase.auth;

  StreamSubscription<KoolbaseUser?>? _sub;

  KoolbaseAuthStatus _status = KoolbaseAuthStatus.restoring;
  KoolbaseUser? _user;
  bool _restoredOffline = false;

  @override
  void initState() {
    super.initState();

    // Deltas only: the auth stream is a broadcast with no initial replay.
    _sub = _auth.authStateChanges.listen(_onAuthChanged);

    // Synchronous seed. If a user is already present (hot restart, gate
    // mounted after login), skip the restore entirely — restoreSession is
    // for cold starts with a persisted session.
    final existing = _auth.currentUser;
    if (existing != null) {
      _status = KoolbaseAuthStatus.signedIn;
      _user = existing;
    } else {
      _restore();
    }
  }

  Future<void> _restore() async {
    RestoreResult result;
    try {
      result = await _auth.restoreSession();
    } catch (_) {
      // A restore that throws is a restore that didn't produce a session.
      // To the user that is signed-out, not an error screen.
      result = RestoreResult.noSession;
    }
    if (!mounted) return;
    setState(() {
      switch (result) {
        case RestoreResult.restored:
          _status = KoolbaseAuthStatus.signedIn;
          _user = _auth.currentUser;
          _restoredOffline = false;
        case RestoreResult.offline:
          // Optimistic restore: user populated, token possibly stale.
          _status = KoolbaseAuthStatus.signedIn;
          _user = _auth.currentUser;
          _restoredOffline = true;
        case RestoreResult.noSession:
        case RestoreResult.expired:
          _status = KoolbaseAuthStatus.signedOut;
          _user = null;
          _restoredOffline = false;
      }
      // Defensive: if the SDK reported a signed-in outcome but holds no
      // user, fail toward signed-out rather than calling signedIn(null!).
      if (_status == KoolbaseAuthStatus.signedIn && _user == null) {
        _status = KoolbaseAuthStatus.signedOut;
      }
    });
  }

  void _onAuthChanged(KoolbaseUser? user) {
    if (!mounted) return;
    setState(() {
      if (user != null) {
        _status = KoolbaseAuthStatus.signedIn;
        _user = user;
      } else {
        _status = KoolbaseAuthStatus.signedOut;
        _user = null;
        _restoredOffline = false;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The slot builders run under a Builder INSIDE the scope, so the
    // context they receive can see KoolbaseAuthScope.of(). Handing them
    // the gate's own context would place them above the scope — the test
    // for restoredOffline caught exactly that.
    return KoolbaseAuthScope(
      status: _status,
      user: _user,
      restoredOffline: _restoredOffline,
      child: Builder(builder: (context) {
        switch (_status) {
          case KoolbaseAuthStatus.restoring:
            return widget.restoring?.call(context) ??
                const Center(child: CircularProgressIndicator());
          case KoolbaseAuthStatus.signedIn:
            return widget.signedIn(context, _user!);
          case KoolbaseAuthStatus.signedOut:
            return widget.signedOut(context);
        }
      }),
    );
  }
}

/// Auth state for descendants of a [KoolbaseAuthGate].
///
/// ```dart
/// final scope = KoolbaseAuthScope.of(context);
/// scope.user;            // KoolbaseUser? — null when signed out
/// scope.status;          // restoring / signedIn / signedOut
/// scope.restoredOffline; // true after an optimistic offline restore
/// ```
///
/// Dependents rebuild when any of these change.
class KoolbaseAuthScope extends InheritedWidget {
  const KoolbaseAuthScope({
    super.key,
    required this.status,
    required this.user,
    required this.restoredOffline,
    required super.child,
  });

  final KoolbaseAuthStatus status;
  final KoolbaseUser? user;

  /// True when the session was restored without network
  /// ([RestoreResult.offline]): the user is populated but the access token
  /// may be stale, and API calls can fail until connectivity returns. Apps
  /// that want an "offline" banner read this.
  final bool restoredOffline;

  static KoolbaseAuthScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<KoolbaseAuthScope>();
    assert(scope != null,
        'KoolbaseAuthScope.of() called outside a KoolbaseAuthGate.');
    return scope!;
  }

  /// Like [of], but returns null instead of asserting when no gate is above
  /// this context — for widgets that work with or without one.
  static KoolbaseAuthScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KoolbaseAuthScope>();

  @override
  bool updateShouldNotify(KoolbaseAuthScope oldWidget) =>
      status != oldWidget.status ||
      user?.id != oldWidget.user?.id ||
      restoredOffline != oldWidget.restoredOffline;
}
