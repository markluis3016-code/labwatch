import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/features/monitoring/domain/telemetry.dart';

void main() {
  test('offline telemetry has unknown states', () {
    final t = LabTelemetry.offline('lab-1');
    expect(t.origin, DataOrigin.offline);
    expect(t.occupied, isNull);
    expect(t.light, PowerState.unknown);
    expect(t.ac, PowerState.unknown);
  });
}
