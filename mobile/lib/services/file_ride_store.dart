import 'dart:io';
import 'dart:typed_data';

import 'ride_store.dart';

/// Rides on the phone, one folder each: `000000.aac.enc`, `000001.aac.enc`, … and `meta.enc`.
/// Every file is sealed (AES-GCM, Android Keystore key) by [seal] and read back by [open].
class FileRideStore implements RideStore {
  FileRideStore(this.root, {required this.seal, required this.open});

  final Directory root;
  final Future<void> Function(String path, Uint8List bytes) seal;
  final Future<Uint8List> Function(String path) open;

  Directory _dir(String tripId) => Directory('${root.path}/$tripId');

  @override
  Future<void> addPiece(String tripId, int index, Uint8List bytes) async {
    final dir = await _dir(tripId).create(recursive: true);
    await seal(
      '${dir.path}/${index.toString().padLeft(6, '0')}.aac.enc',
      bytes,
    );
  }

  @override
  Future<Uint8List> audio(String tripId) async {
    final pieces =
        _dir(tripId)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.aac.enc'))
            .map((f) => f.path)
            .toList()
          ..sort();
    final b = BytesBuilder(copy: false);
    for (final p in pieces) {
      b.add(await open(p));
    }
    return b.takeBytes();
  }

  @override
  Future<void> save(RideMeta meta) async {
    final dir = await _dir(meta.tripId).create(recursive: true);
    await seal('${dir.path}/meta.enc', meta.encode());
  }

  @override
  Future<List<RideMeta>> rides() async {
    if (!root.existsSync()) return [];
    final out = <RideMeta>[];
    for (final dir in root.listSync().whereType<Directory>()) {
      final meta = File('${dir.path}/meta.enc');
      if (!meta.existsSync()) continue;
      try {
        out.add(RideMeta.decode(await open(meta.path)));
      } catch (_) {
        // A file sealed by a key that no longer exists (app reinstalled) can't be read: drop it.
        await dir.delete(recursive: true);
      }
    }
    return out;
  }

  @override
  Future<void> delete(String tripId) async {
    final dir = _dir(tripId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
