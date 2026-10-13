import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Check if biometric hardware is present and enrolled
  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Prompt biometric challenge before sensitive action
  Future<bool> authenticate({
    String reason = 'Authenticate to dispatch command to Antigravity Host',
  }) async {
    try {
      final isSupported = await canCheckBiometrics();
      if (!isSupported) {
        // Fallback for emulators or devices without hardware sensor
        return true;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows device PIN fallback if biometric fails
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      // Return false on explicit cancel or error
      return false;
    }
  }
}
