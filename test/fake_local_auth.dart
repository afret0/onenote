import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

class FakeLocalAuth extends LocalAuthPlatform {
  FakeLocalAuth({
    this.canCheck = true,
    this.deviceSupported = true,
    this.enrolled = const [BiometricType.fingerprint],
    this.authResult = true,
  });

  bool canCheck;
  bool deviceSupported;
  List<BiometricType> enrolled;
  bool authResult;
  int authCalls = 0;
  String? lastReason;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authCalls++;
    lastReason = localizedReason;
    return authResult;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => canCheck;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => enrolled;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;
}