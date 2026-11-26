import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gosafe/services/file_ride_store.dart';
import 'package:gosafe/services/ride_store.dart';

void main() {
  late Directory root;
  late FileRideStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('rides');
    // Reverses the bytes instead of AES, so the test can tell sealed files from plain ones.
    store = FileRideStore(
      root,
      seal: (path, bytes) async =>
          File(path).writeAsBytes(bytes.reversed.toList()),
      open: (path) async => Uint8List.fromList(
        (await File(path).readAsBytes()).reversed.toList(),
      ),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('pieces are counted and read back by number', () async {
    for (final i in [0, 1, 2]) {
      await store.addPiece('GR-1', i, Uint8List.fromList([i, 9]));
    }
    expect(await store.pieceCount('GR-1'), 3);
    expect(await store.piece('GR-1', 2), [2, 9]);
    expect(await store.pieceCount('GR-NONE'), 0);
  });

  test('details round-trip, and a ride is deleted with its folder', () async {
    final meta = RideMeta(
      tripId: 'GR-1',
      startedAt: DateTime.utc(2026, 11, 26, 9),
      contentType: 'audio/aac',
      role: 'driver',
      share: Share.live,
      piecesSent: 4,
      markers: [
        {'at': 3.5, 'kind': 'high', 'label': 'threat', 'score': 0.9},
      ],
      transcript: [
        {'at': 3.5, 'text': 'Diam atau saya turunkan di sini.'},
      ],
    );
    await store.save(meta);
    final back = (await store.rides()).single;
    expect(back.toJson(), meta.toJson());
    expect((back.role, back.share, back.piecesSent), ('driver', Share.live, 4));

    await store.delete('GR-1');
    expect(await store.rides(), isEmpty);
    expect(root.listSync(), isEmpty);
  });

  test('a ride whose details can no longer be opened is dropped', () async {
    await store.addPiece('GR-1', 0, Uint8List.fromList([1]));
    File('${root.path}/GR-1/meta.enc').writeAsStringSync('not json');
    expect(await store.rides(), isEmpty);
    expect(Directory('${root.path}/GR-1').existsSync(), isFalse);
  });

  test('the safe phrase is kept sealed and read back', () async {
    expect(await store.safePhrase(), isNull);
    await store.setSafePhrase('Pak, nanti lewat jalan biasa aja ya');
    expect(await store.safePhrase(), 'Pak, nanti lewat jalan biasa aja ya');
    expect(
      File('${root.path}/safe_phrase.enc').readAsStringSync(),
      isNot(contains('lewat')),
      reason: 'never in plain text',
    );
    expect(await store.rides(), isEmpty, reason: 'not mistaken for a ride');
  });
}
