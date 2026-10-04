import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'realtime_models.dart';

/// One open realtime connection, as the client uses it: what arrives, how to
/// send, how to close. The client opens it through a [RealtimeConnector], so
/// its lifecycle can be tested without a server.
class RealtimeConnection {
  final Stream<dynamic> stream;
  final void Function(String message) send;
  final void Function() close;

  const RealtimeConnection({
    required this.stream,
    required this.send,
    required this.close,
  });
}

/// Opens a [RealtimeConnection] to [uri]. The default is a WebSocket.
typedef RealtimeConnector = RealtimeConnection Function(Uri uri);

RealtimeConnection _webSocket(Uri uri) {
  final channel = WebSocketChannel.connect(uri);
  return RealtimeConnection(
    stream: channel.stream,
    send: channel.sink.add,
    close: () => unawaited(channel.sink.close()),
  );
}

/// Koolbase realtime: one connection for the whole app, shared by every
/// collection followed through [on].
///
/// A collection is subscribed while its stream has a listener and
/// unsubscribed when the last one leaves. The connection opens for the first
/// listener and closes [idleGrace] after the last one leaves -- a moment, so a
/// screen that comes straight back keeps the connection it had.
class KoolbaseRealtimeClient {
  final String baseUrl;
  final String publicKey;
  final Future<String?> Function() accessTokenProvider;

  /// Who is signed in: their user id, or null when signed out. Signed out,
  /// the client connects with [publicKey] and sees only collections anyone
  /// can read. Without a provider, a missing token means signed out.
  final String? Function()? userIdProvider;
  final RealtimeConnector _connector;
  final Duration _idleGrace;

  String? _token;
  String? _projectId; // derived from the session token
  RealtimeConnection? _connection;
  Timer? _reconnectTimer;
  Timer? _idleTimer;
  bool _disposed = false;
  bool _connecting = false;

  // The open connection is a signed-out visitor's (the public key): its
  // messages leave project_id out.
  bool _anonymous = false;
  // Whose session the open connection was made for: the user id, or null
  // when signed out. sessionChanged compares against it.
  String? _connectedAs;
  // Bumped by sessionChanged: a connect still waiting for its token gives up
  // rather than open a connection for the old session.
  int _generation = 0;

  // Keyed by collection -- one user session means one project. A controller
  // stays for the client's life; whether it is subscribed follows its
  // listeners (onListen / onCancel).
  final Map<String, StreamController<RealtimeEvent>> _controllers = {};
  final Set<String> _subscriptions = {};

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  KoolbaseRealtimeClient({
    required this.baseUrl,
    required this.publicKey,
    required this.accessTokenProvider,
    this.userIdProvider,
    RealtimeConnector? connector,
    Duration idleGrace = const Duration(seconds: 1),
  })  : _connector = connector ?? _webSocket,
        _idleGrace = idleGrace;

  Stream<bool> get connectionState => _connectionController.stream;

  String get _wsUrl {
    final base = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final credential = _anonymous
        ? 'public_key=${Uri.encodeQueryComponent(publicKey)}'
        : 'token=$_token';
    return '$base/v1/realtime/ws?$credential';
  }

  /// Extracts the project_id claim from a Koolbase session JWT.
  static String? _projectIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final map = jsonDecode(utf8.decode(base64.decode(payload)))
          as Map<String, dynamic>;
      return map['project_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || _connection != null) return;
    _connecting = true;

    final generation = _generation;
    String? token;
    try {
      token = await accessTokenProvider();
    } catch (_) {
      // A session that could not be refreshed is still a session: try again
      // later, never as a signed-out visitor.
      if (generation != _generation) return;
      _connecting = false;
      _scheduleReconnect();
      return;
    }
    // The session changed while the token was on its way: sessionChanged has
    // started the connection for the new one.
    if (generation != _generation) return;
    if (_disposed || _subscriptions.isEmpty) {
      // Everyone left while the token was on its way: nothing to connect for.
      _connecting = false;
      return;
    }
    final userId = userIdProvider?.call();
    if (token == null && userId != null) {
      // Signed in, but no usable token right now: try again later rather
      // than drop to public-only.
      _connecting = false;
      _scheduleReconnect();
      return;
    }
    // Signed out: the project's public key, and only collections anyone can
    // read. The server pins the connection to the key's project.
    _anonymous = token == null;
    _connectedAs = token == null ? null : userId;
    _token = token;
    _projectId = token == null ? null : _projectIdFromToken(token);
    if (!_anonymous && _projectId == null) {
      _connecting = false;
      _scheduleReconnect();
      return;
    }

    final RealtimeConnection connection;
    try {
      connection = _connector(Uri.parse(_wsUrl));
    } catch (_) {
      _connecting = false;
      _scheduleReconnect();
      return;
    }
    _connection = connection;
    _connecting = false;

    Future.microtask(() {
      if (_disposed || _connection != connection) return;
      _emitConnection(true);
      for (final collection in _subscriptions) {
        _sendSubscribe(collection);
      }
    });

    connection.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final event = RealtimeEvent.fromJson(json);
          _dispatch(event);
        } catch (e) {
          // Ignore malformed messages
        }
      },
      onDone: () => _lost(connection),
      onError: (Object _) => _lost(connection),
      cancelOnError: true,
    );
  }

  /// A connection that ended without us closing it: try again.
  void _lost(RealtimeConnection connection) {
    if (_connection != connection) return; // one we closed on purpose
    _connection = null;
    _emitConnection(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _subscriptions.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed) _connect();
    });
  }

  /// Closes the connection once nothing listens -- after [_idleGrace], so a
  /// listener that comes straight back keeps it. Nothing reconnects after
  /// this: reconnecting needs a subscription.
  void _scheduleIdleClose() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleGrace, () {
      _idleTimer = null;
      if (_disposed || _subscriptions.isNotEmpty) return;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      final connection = _connection;
      _connection = null;
      if (connection != null) {
        connection.close();
        _emitConnection(false);
      }
    });
  }

  void _emitConnection(bool connected) {
    if (!_connectionController.isClosed) _connectionController.add(connected);
  }

  void _sendSubscribe(String collection) => _send('subscribe', collection);

  void _sendUnsubscribe(String collection) => _send('unsubscribe', collection);

  /// A signed-out visitor's message leaves project_id out: it has none to
  /// give, and the server uses the public key's project.
  void _send(String action, String collection) {
    final connection = _connection;
    if (connection == null) return;
    if (_anonymous) {
      connection.send(jsonEncode({'action': action, 'collection': collection}));
      return;
    }
    final pid = _projectId;
    if (pid == null) return;
    connection.send(jsonEncode({
      'action': action,
      'project_id': pid,
      'collection': collection,
    }));
  }

  void _dispatch(RealtimeEvent event) {
    final collection = event.collection; // from payload; null on acks/errors
    if (collection == null) return;
    _controllers[collection]?.add(event);
  }

  /// The collection's first listener: subscribe, connecting if need be.
  void _listened(String collection) {
    if (_disposed) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_subscriptions.add(collection)) return;
    if (_connection != null) {
      _sendSubscribe(collection);
    } else {
      unawaited(_connect());
    }
  }

  /// The collection's last listener left: unsubscribe; close the connection
  /// a moment later if nothing else listens.
  void _unlistened(String collection) {
    if (_disposed || !_subscriptions.remove(collection)) return;
    _sendUnsubscribe(collection);
    if (_subscriptions.isEmpty) _scheduleIdleClose();
  }

  /// The signed-in user changed: signed in, signed out, or another user. The
  /// open connection was made for the previous session -- signed out it sees
  /// only public collections, signed in it carries that user's access -- so
  /// it is replaced by one for the new session, resubscribing every
  /// collection. The same user again (a token refresh) changes nothing, and
  /// with nothing open there is nothing to do: the next listener connects as
  /// whoever is signed in then.
  void sessionChanged() {
    if (_disposed) return;
    if (_connection == null &&
        !_connecting &&
        _reconnectTimer?.isActive != true) {
      return;
    }
    if (_connection != null && userIdProvider?.call() == _connectedAs) return;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final connection = _connection;
    _connection = null; // first: this close is ours, not a lost connection
    _connecting = false;
    _anonymous = false;
    _projectId = null;
    if (connection != null) {
      connection.close();
      _emitConnection(false);
    }
    if (_subscriptions.isNotEmpty) unawaited(_connect());
  }

  /// Subscribe to a collection -- returns a stream of realtime events.
  /// The project is taken from the signed-in user's session; signed out,
  /// from [publicKey], and only a collection anyone can read delivers. Subscribed while
  /// the stream has a listener; any number of listeners share one
  /// subscription.
  Stream<RealtimeEvent> on({required String collection}) {
    final controller =
        _controllers[collection] ??= StreamController<RealtimeEvent>.broadcast(
      onListen: () => _listened(collection),
      onCancel: () => _unlistened(collection),
    );
    return controller.stream;
  }

  Stream<Map<String, dynamic>> onRecordCreated({required String collection}) {
    return on(collection: collection)
        .where((e) => e.type == RealtimeEventType.recordCreated)
        .where((e) => e.record != null)
        .map((e) => e.record!);
  }

  Stream<Map<String, dynamic>> onRecordUpdated({required String collection}) {
    return on(collection: collection)
        .where((e) => e.type == RealtimeEventType.recordUpdated)
        .where((e) => e.record != null)
        .map((e) => e.record!);
  }

  Stream<String> onRecordDeleted({required String collection}) {
    return on(collection: collection)
        .where((e) => e.type == RealtimeEventType.recordDeleted)
        .where((e) => e.recordId != null)
        .map((e) => e.recordId!);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _idleTimer?.cancel();
    _connection?.close();
    _connection = null;
    _connectionController.close();
    for (final ctrl in _controllers.values) {
      ctrl.close();
    }
    _controllers.clear();
    _subscriptions.clear();
  }
}
