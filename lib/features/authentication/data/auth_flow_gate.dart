import 'package:flutter/foundation.dart';

/// Coordinates multi-step auth flows (sign-up) with the router. While a flow
/// is busy the router must not react to transient states such as "signed in
/// but the profile document has not been written yet".
class AuthFlowGate {
  AuthFlowGate._();

  static final AuthFlowGate instance = AuthFlowGate._();

  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  void begin() => busy.value = true;

  void end() => busy.value = false;
}
