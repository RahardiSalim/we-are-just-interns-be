import 'api.dart';
import 'ride_store.dart';

/// Sends what the backend doesn't have yet of one ride: the details, then every audio piece not
/// sent yet, then the details again with the new count. Safe to call again after a failure: it
/// picks up at the first piece not sent. `done`: the ride ended and this is the last call.
Future<void> syncRide(
  Api api,
  RideStore store,
  RideMeta ride, {
  required bool done,
  Future<void> Function()?
  save, // the ride screen's own writer for the ride in progress
}) async {
  final persist = save ?? () => store.save(ride);
  final live = ride.share == Share.live && !done;
  // The details go first: the backend only hands out piece links for a ride it may receive.
  await api.saveRecording(
    ride,
    pieces: ride.piecesSent,
    live: live,
    done: false,
  );
  final count = await store.pieceCount(ride.tripId);
  for (var n = ride.piecesSent; n < count; n++) {
    await api.uploadPiece(
      ride.tripId,
      n,
      ride.contentType,
      await store.piece(ride.tripId, n),
    );
    ride.piecesSent = n + 1;
    await persist();
  }
  await api.saveRecording(ride, pieces: count, live: live, done: done);
  if (done) {
    ride.uploaded = true;
    await persist();
  }
}
