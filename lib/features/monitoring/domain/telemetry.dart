/// Where a reading came from. The UI must always show this to the user.
enum DataOrigin { live, sample, offline }

enum PowerState { on, off, unknown }

class LabTelemetry {
  const LabTelemetry({
    required this.labId,
    required this.origin,
    required this.occupied,
    required this.light,
    required this.ac,
    required this.sensorTimestamp,
    this.receivedAt,
  });

  final String labId;
  final DataOrigin origin;

  /// null = occupancy sensor gave no usable value.
  final bool? occupied;
  final PowerState light;
  final PowerState ac;

  /// Timestamp reported by the device.
  final DateTime? sensorTimestamp;

  /// Time the app/backend received it.
  final DateTime? receivedAt;

  /// Reading used when no data exists at all.
  factory LabTelemetry.offline(String labId) => LabTelemetry(
        labId: labId,
        origin: DataOrigin.offline,
        occupied: null,
        light: PowerState.unknown,
        ac: PowerState.unknown,
        sensorTimestamp: null,
      );
}

/// Validates and classifies a raw reading. Pure function: easy to unit test.
class TelemetryValidator {
  TelemetryValidator({
    this.staleAfter = const Duration(minutes: 2),
    this.maxClockSkew = const Duration(minutes: 5),
  });

  final Duration staleAfter;
  final Duration maxClockSkew;

  /// Returns the reading with origin downgraded to [DataOrigin.offline] when
  /// the timestamp is missing, in the future beyond tolerated skew, or stale.
  /// Sample readings are passed through unchanged so they stay labelled SAMPLE.
  LabTelemetry validate(LabTelemetry t, DateTime now) {
    if (t.origin == DataOrigin.sample) return t;
    final ts = t.sensorTimestamp;
    if (ts == null) return LabTelemetry.offline(t.labId);
    if (ts.isAfter(now.add(maxClockSkew))) return LabTelemetry.offline(t.labId);
    if (now.difference(ts) > staleAfter) {
      return LabTelemetry(
        labId: t.labId,
        origin: DataOrigin.offline,
        occupied: null,
        light: PowerState.unknown,
        ac: PowerState.unknown,
        sensorTimestamp: ts,
        receivedAt: t.receivedAt,
      );
    }
    return t;
  }
}
