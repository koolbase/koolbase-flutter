import 'package:flutter/material.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

/// Drives the offline write path by hand, because the parts that matter cannot
/// be shown by a unit test: whether a real network failure takes the offline
/// branch, whether the queue survives a restart, and whether a genuine
/// concurrent edit becomes a conflict rather than an overwrite.
class OfflineProbe extends StatefulWidget {
  const OfflineProbe({super.key});

  @override
  State<OfflineProbe> createState() => _OfflineProbeState();
}

class _OfflineProbeState extends State<OfflineProbe> {
  static const _collection = 'offline_probe';

  final _log = <String>[];
  String? _recordId;
  int? _revision;
  List<KoolbaseConflict> _conflicts = const [];

  void _say(String line) {
    setState(() => _log.insert(0, line));
    debugPrint('[probe] $line');
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    try {
      await body();
    } on KoolbaseOfflineBaselineUnavailableException catch (e) {
      _say('$label → refused: ${e.message}');
    } on KoolbaseRevisionMismatchException catch (e) {
      _say('$label → conflict: expected ${e.expectedRevision}, now ${e.currentRevision}');
    } on KoolbaseDataException catch (e) {
      _say('$label → ${e.code ?? "error"}: ${e.message}');
    } catch (e) {
      _say('$label → $e');
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final c = await Koolbase.db.conflicts();
    setState(() => _conflicts = c);
  }

  Future<void> _signIn() => _guard('sign in', () async {
        final email = 'probe-${DateTime.now().millisecondsSinceEpoch}@test.local';
        await Koolbase.auth.signUp(email: email, password: 'probe-password-123');
        _say('signed in as $email');
      });

  Future<void> _create() => _guard('create', () async {
        final rec = await Koolbase.db.insert(
          collection: _collection,
          data: {'label': 'first', 'n': 1},
        );
        setState(() {
          _recordId = rec.id;
          _revision = rec.revision;
        });
        _say('created ${rec.id} at revision ${rec.revision}');
      });

  Future<void> _read() => _guard('read', () async {
        final rec = await Koolbase.db.doc(_recordId!).get();
        setState(() => _revision = rec.revision);
        _say('read revision ${rec.revision}: ${rec.data}');
      });

  Future<void> _update() => _guard('update', () async {
        final rec = await Koolbase.db.doc(_recordId!).update({
          'label': 'edited at ${DateTime.now().toIso8601String().substring(11, 19)}',
        });
        _say('update returned revision ${rec.revision}');
      });

  Future<void> _delete() => _guard('delete', () async {
        await Koolbase.db.doc(_recordId!).delete();
        _say('delete returned');
      });

  Future<void> _sync() => _guard('sync', () async {
        await Koolbase.db.syncPendingWrites();
        _say('sync pass finished');
      });

  // The record has never been read on this device, so there is nothing to
  // compose a change against and the SDK should refuse rather than queue.
  Future<void> _updateUnseen() => _guard('update unseen', () async {
        await Koolbase.db.doc('00000000-0000-0000-0000-000000000000').update({'x': 1});
        _say('unseen update returned — expected a refusal');
      });

  @override
  Widget build(BuildContext context) {
    final ready = _recordId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline probe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(onPressed: _signIn, child: const Text('1. sign in')),
              ElevatedButton(onPressed: _create, child: const Text('2. create')),
              ElevatedButton(onPressed: ready ? _read : null, child: const Text('3. read')),
              ElevatedButton(onPressed: ready ? _update : null, child: const Text('4. update')),
              ElevatedButton(onPressed: ready ? _delete : null, child: const Text('5. delete')),
              ElevatedButton(onPressed: _sync, child: const Text('6. sync')),
              OutlinedButton(onPressed: _updateUnseen, child: const Text('update unseen')),
              OutlinedButton(onPressed: _refresh, child: const Text('refresh')),
            ]),
          ),
          if (_recordId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('record $_recordId · revision $_revision',
                  style: const TextStyle(fontSize: 12)),
            ),
          if (_conflicts.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_conflicts.length} conflict(s)',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  for (final c in _conflicts) ...[
                    Text('${c.operation.name} ${c.recordId} — '
                        'fields: ${c.divergentFields.join(", ")}'),
                    Text('  yours: ${c.local}', style: const TextStyle(fontSize: 11)),
                    Text('  theirs: ${c.server}', style: const TextStyle(fontSize: 11)),
                    Row(children: [
                      TextButton(
                          onPressed: () => _guard('resolve local', c.resolveWithLocal),
                          child: const Text('keep mine')),
                      TextButton(
                          onPressed: () => _guard('resolve server', c.resolveWithServer),
                          child: const Text('keep theirs')),
                      TextButton(
                          onPressed: () => _guard('abandon', c.abandon),
                          child: const Text('abandon')),
                    ]),
                  ],
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(_log[i], style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
