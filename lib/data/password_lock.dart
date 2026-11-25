import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class PasswordLock {
  const PasswordLock({
    required this.salt,
    required this.hash,
    required this.updateAt,
    this.cleared = false,
  });

  static const argon2MemoryKib = 19456;
  static const argon2Iterations = 2;
  static const argon2Lanes = 1;
  static const _saltBytes = 16;
  static const _hashBytes = 32;

  final String salt;
  final String hash;
  final int updateAt;
  final bool cleared;

  bool get active => !cleared && salt.isNotEmpty && hash.isNotEmpty;

  static PasswordLock? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return PasswordLock.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  factory PasswordLock.fromJson(Map<String, dynamic> json) => PasswordLock(
        salt: json['salt'] as String? ?? '',
        hash: json['hash'] as String? ?? '',
        updateAt: (json['updateAt'] as num?)?.toInt() ?? 0,
        cleared: json['cleared'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (salt.isNotEmpty) 'salt': salt,
        if (hash.isNotEmpty) 'hash': hash,
        'updateAt': updateAt,
        if (cleared) 'cleared': true,
      };

  String encode() => jsonEncode(toJson());

  static PasswordLock clearedAt(int updateAt) =>
      PasswordLock(salt: '', hash: '', updateAt: updateAt, cleared: true);

  static PasswordLock create(String password, int updateAt) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
        List.generate(_saltBytes, (_) => random.nextInt(256)));
    return PasswordLock(
      salt: base64Encode(salt),
      hash: base64Encode(derive(password, salt)),
      updateAt: updateAt,
    );
  }

  bool verify(String password) {
    if (!active) {
      return false;
    }
    try {
      final expected = base64Decode(hash);
      final actual = derive(password, base64Decode(salt));
      if (expected.length != actual.length) {
        return false;
      }
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= expected[i] ^ actual[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  static Uint8List derive(String password, Uint8List salt) {
    final generator = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: _hashBytes,
        iterations: argon2Iterations,
        memory: argon2MemoryKib,
        lanes: argon2Lanes,
      ));
    final out = Uint8List(_hashBytes);
    generator.deriveKey(
        Uint8List.fromList(utf8.encode(password)), 0, out, 0);
    return out;
  }
}

class PrivacySpaceRef {
  const PrivacySpaceRef({
    required this.id,
    required this.lock,
    this.createAt = 0,
    this.cleared = false,
  });

  final String id;
  final PasswordLock lock;
  final int createAt;
  final bool cleared;

  bool get active => !cleared && id.isNotEmpty && lock.active;

  static PrivacySpaceRef? parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return PrivacySpaceRef.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  factory PrivacySpaceRef.fromJson(Map<String, dynamic> json) =>
      PrivacySpaceRef(
        id: json['id'] as String? ?? '',
        lock: PasswordLock.fromJson(json),
        createAt: (json['createAt'] as num?)?.toInt() ?? 0,
        cleared: json['cleared'] == true,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        ...lock.toJson(),
        if (createAt > 0) 'createAt': createAt,
        if (cleared) 'cleared': true,
      };

  String encode() => jsonEncode(toJson());

  static PrivacySpaceRef clearedAt(int updateAt) => PrivacySpaceRef(
      id: '', lock: PasswordLock.clearedAt(updateAt), cleared: true);
}