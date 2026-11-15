import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/features/monitoring/domain/telemetry.dart';

LabTelemetry _live(DateTime? ts) => LabTelemetry(
      labId: 'lab-1',
      origin: DataOrigin.live,
      occupied: true,
      light: PowerState.on,
      ac: PowerState.on,
      sensorTimestamp: ts,
    );

void main() {
  final now = DateTime(2026, 11, 15, 12);
  final v = TelemetryValidator();

  test('fresh live reading stays live', () {
    final r = v.validate(_live(now.subtract(const Duration(seconds: 10))), now);
    expect(r.origin, DataOrigin.live);
    expect(r.occupied, true);
  });

  test('stale reading becomes offline with unknown states', () {
    final r = v.validate(_live(now.subtract(const Duration(minutes: 10))), now);
    expect(r.origin, DataOrigin.offline);
    expect(r.occupied, isNull);
    expect(r.light, PowerState.unknown);
  });

  test('missing timestamp becomes offline', () {
    expect(v.validate(_live(null), now).origin, DataOrigin.offline);
  });

  test('timestamp far in the future is rejected', () {
    final r = v.validate(_live(now.add(const Duration(hours: 1))), now);
    expect(r.origin, DataOrigin.offline);
  });

  test('sample data is never promoted to live', () {
    final s = LabTelemetry(
      labId: 'lab-1',
      origin: DataOrigin.sample,
      occupied: false,
      light: PowerState.on,
      ac: PowerState.off,
      sensorTimestamp: now,
    );
    expect(v.validate(s, now).origin, DataOrigin.sample);
  });
}
