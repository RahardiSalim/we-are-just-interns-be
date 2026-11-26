import 'dart:convert';
import 'dart:typed_data';

/// How long the phone keeps a ride (audio and details), then deletes it. Matches the consent text.
const keepFor = Duration(days: 7);

/// How much of a ride leaves the phone. It only ever goes up during a ride.
enum Share {
  /// Nothing: kept encrypted on the phone for 7 days.
  local,

  /// The whole ride (audio, transcript, flags) when it ends: after a report or a high flag.
  atEnd,

  /// Streamed to an agent while the ride is on: after an SOS, "I need help", the safe phrase,
  /// a shout for help, or a high flag nobody answered for 60 seconds.
  live,
}

/// What the phone keeps about one ride next to its audio, saved as the ride goes,
/// so a crash or a killed app loses at most the last piece.
class RideMeta {
  RideMeta({
    required this.tripId,
    required this.startedAt,
    required this.contentType,
    this.role = 'rider',
    this.share = Share.local,
    this.piecesSent = 0,
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

  /// Whose phone: `rider` or `driver`.
  final String role;
  Share share;

  /// Audio pieces already uploaded (pieces are numbered from 0).
  int piecesSent;
  double durationSec;
  bool ended;
  bool uploaded;

  /// `Marker.toJson()`: the moments an agent should check.
  final List<Map<String, Object?>> markers;

  /// `{at, text}` per line heard, seconds from the start of the recording.
  final List<Map<String, Object?>> transcript;

  Map<String, Object?> toJson() => {
    'tripId': tripId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'contentType': contentType,
    'role': role,
    'share': share.name,
    'piecesSent': piecesSent,
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
    role: j['role'] as String? ?? 'rider',
    share: Share.values.byName(j['share'] as String? ?? 'local'),
    piecesSent: j['piecesSent'] as int? ?? 0,
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

  /// How many audio pieces the ride has (numbered from 0).
  Future<int> pieceCount(String tripId);
  Future<Uint8List> piece(String tripId, int index);
  Future<void> save(RideMeta meta);
  Future<List<RideMeta>> rides();
  Future<void> delete(String tripId);

  /// The user's own safe phrase (the hands-free alarm), kept encrypted with the rides. Null until set.
  Future<String?> safePhrase();
  Future<void> setSafePhrase(String phrase);
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
  String? _phrase;

  @override
  Future<String?> safePhrase() async => _phrase;

  @override
  Future<void> setSafePhrase(String phrase) async => _phrase = phrase;

  @override
  Future<void> addPiece(String tripId, int index, Uint8List bytes) async =>
      (_pieces[tripId] ??= {})[index] = bytes;

  @override
  Future<int> pieceCount(String tripId) async => _pieces[tripId]?.length ?? 0;

  @override
  Future<Uint8List> piece(String tripId, int index) async =>
      _pieces[tripId]![index]!;

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
