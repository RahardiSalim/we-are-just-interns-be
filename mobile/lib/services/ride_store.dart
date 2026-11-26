import 'dart:convert';
import 'dart:typed_data';

/// How long the phone keeps a ride (audio and details), then deletes it. Matches the consent text.
const keepFor = Duration(days: 7);

/// What the phone keeps about one ride next to its audio, saved as the ride goes,
/// so a crash or a killed app loses at most the last piece.
class RideMeta {
  RideMeta({
    required this.tripId,
    required this.startedAt,
    required this.contentType,
    this.durationSec = 0,
    this.ended = false,
    this.uploaded = false,
    List<Map<String, Object?>>? markers,
    List<Map<String, Object?>>? transcript,
  }) : markers = markers ?? [],
       transcript = transcript ?? [];

  final String tripId;
  final DateTime startedAt;
  final String contentType;
  double durationSec;
  bool ended;
  bool uploaded;

  /// `Marker.toJson()`: the moments an agent should check.
  final List<Map<String, Object?>> markers;

  /// `{at, text}` per line heard, seconds from the start of the recording.
  final List<Map<String, Object?>> transcript;

  /// Only a ride with a high flag or an SOS sends its recording.
  bool get flagged =>
      markers.any((m) => m['kind'] == 'high' || m['kind'] == 'sos');

  Map<String, Object?> toJson() => {
    'tripId': tripId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'contentType': contentType,
    'durationSec': durationSec,
    'ended': ended,
    'uploaded': uploaded,
    'markers': markers,
    'transcript': transcript,
  };

  factory RideMeta.fromJson(Map<String, Object?> j) => RideMeta(
    tripId: j['tripId'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
    contentType: j['contentType'] as String,
    durationSec: (j['durationSec'] as num).toDouble(),
    ended: j['ended'] as bool,
    uploaded: j['uploaded'] as bool,
    markers: [for (final m in j['markers'] as List) (m as Map).cast()],
    transcript: [for (final t in j['transcript'] as List) (t as Map).cast()],
  );

  Uint8List encode() => utf8.encode(jsonEncode(toJson()));
  static RideMeta decode(Uint8List bytes) =>
      RideMeta.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, Object?>);
}

/// Every ride's audio, in numbered pieces, and its [RideMeta]. Encrypted on Android
/// ([FileRideStore]); in memory for the web preview and tests.
abstract interface class RideStore {
  Future<void> addPiece(String tripId, int index, Uint8List bytes);

  /// All pieces in order, joined. AAC in ADTS frames joins byte for byte.
  Future<Uint8List> audio(String tripId);
  Future<void> save(RideMeta meta);
  Future<List<RideMeta>> rides();
  Future<void> delete(String tripId);
}

/// Deletes rides older than [keepFor] and returns the ones kept.
Future<List<RideMeta>> tidy(RideStore store, DateTime now) async {
  final kept = <RideMeta>[];
  for (final r in await store.rides()) {
    if (now.difference(r.startedAt) > keepFor) {
      await store.delete(r.tripId);
    } else {
      kept.add(r);
    }
  }
  return kept;
}

class MemoryRideStore implements RideStore {
  final _pieces = <String, Map<int, Uint8List>>{};
  final _meta = <String, Uint8List>{};

  @override
  Future<void> addPiece(String tripId, int index, Uint8List bytes) async =>
      (_pieces[tripId] ??= {})[index] = bytes;

  @override
  Future<Uint8List> audio(String tripId) async {
    final p = _pieces[tripId] ?? {};
    final b = BytesBuilder(copy: false);
    for (final i in p.keys.toList()..sort()) {
      b.add(p[i]!);
    }
    return b.takeBytes();
  }

  @override
  Future<void> save(RideMeta meta) async => _meta[meta.tripId] = meta.encode();

  @override
  Future<List<RideMeta>> rides() async => [
    for (final m in _meta.values) RideMeta.decode(m),
  ];

  @override
  Future<void> delete(String tripId) async {
    _pieces.remove(tripId);
    _meta.remove(tripId);
  }
}
