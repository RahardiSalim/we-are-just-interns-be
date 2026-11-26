import 'dart:convert';
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

  String _piecePath(String tripId, int index) =>
      '${_dir(tripId).path}/${index.toString().padLeft(6, '0')}.aac.enc';

  @override
  Future<int> pieceCount(String tripId) async {
    final dir = _dir(tripId);
    if (!dir.existsSync()) return 0;
    return dir.listSync().where((f) => f.path.endsWith('.aac.enc')).length;
  }

  @override
  Future<Uint8List> piece(String tripId, int index) =>
      open(_piecePath(tripId, index));

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

  File get _phraseFile => File('${root.path}/safe_phrase.enc');

  @override
  Future<String?> safePhrase() async {
    if (!_phraseFile.existsSync()) return null;
    try {
      return utf8.decode(await open(_phraseFile.path));
    } catch (_) {
      return null; // sealed by a key that's gone (app reinstalled): ask again
    }
  }

  @override
  Future<void> setSafePhrase(String phrase) async {
    await root.create(recursive: true);
    await seal(_phraseFile.path, utf8.encode(phrase));
  }

  @override
  Future<void> delete(String tripId) async {
    final dir = _dir(tripId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
