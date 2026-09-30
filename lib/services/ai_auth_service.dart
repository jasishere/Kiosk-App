import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Outcome of authenticating one banknote.
class AuthResult {
  /// True only when the classifier cleared the note outright.
  final bool authentic;

  /// Denomination the classifier read, or null if it could not read one.
  final int? denomination;

  /// 0..1 classifier confidence.
  final double confidence;

  /// Set when the call itself failed (service down, timeout, bad payload)
  /// as opposed to the note being judged counterfeit. The distinction
  /// matters: a service outage must never be reported to the customer as
  /// "your money is fake".
  final String? errorMessage;

  const AuthResult({
    required this.authentic,
    this.denomination,
    this.confidence = 0.0,
    this.errorMessage,
  });

  bool get isServiceError => errorMessage != null;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final raw = json['denomination'];
    final denomination =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;

    return AuthResult(
      authentic: json['authentic'] == true,
      denomination: denomination,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  factory AuthResult.error(String message) =>
      AuthResult(authentic: false, errorMessage: message);
}

/// Client for the local Python service that wraps the OpenCV/YOLOv8
/// banknote classifier (Pi Camera V3 under 365 nm UV, per the thesis).
///
/// HTTP rather than calling Python from Dart keeps the ML stack completely
/// decoupled: you can retrain, swap weights, or rewrite the classifier
/// without touching Flutter. The service runs on the same Pi, bound to
/// loopback only — it must never be reachable from the network.
///
/// Contract the service must implement:
///
///   GET  /health       → 200 once the model is loaded and the camera opened
///   POST /authenticate → captures under UV and classifies
///                        { "authentic": true, "denomination": 100,
///                          "confidence": 0.97 }
///
/// See docs/HARDWARE.md for the full sequence and a runnable reference stub.
class AiAuthService {
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  AiAuthService({
    this.baseUrl = AppConfig.aiBaseUrl,
    this.timeout = const Duration(seconds: 8),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final _online = StreamController<bool>.broadcast();
  Timer? _poll;
  bool _lastOnline = false;
  bool _disposed = false;

  /// Emits on transition only, so a long outage doesn't spam listeners.
  Stream<bool> get onlineState => _online.stream;
  bool get isOnline => _lastOnline;

  /// Begins periodic health polling. The previous version checked once at
  /// startup, which meant a classifier that died at 9am showed as online all
  /// day and failed at the worst possible moment — mid-transaction, with the
  /// customer's note already in escrow.
  void startHealthMonitor() {
    _poll?.cancel();
    unawaited(_checkHealth());
    _poll = Timer.periodic(AppConfig.aiHealthInterval, (_) => _checkHealth());
  }

  Future<bool> _checkHealth() async {
    final ok = await healthCheck();
    if (ok != _lastOnline && !_disposed) {
      _lastOnline = ok;
      _online.add(ok);
    }
    return ok;
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Authenticates the note currently held in escrow. Call only after the
  /// Arduino has reported `BILL_STAGED` and UV illumination is on.
  Future<AuthResult> authenticate() async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/authenticate'),
            headers: const {'Content-Type': 'application/json'},
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return AuthResult.error(
          'Classifier returned HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return AuthResult.error('Classifier returned an unexpected payload');
      }
      return AuthResult.fromJson(decoded);
    } on TimeoutException {
      return AuthResult.error('Classifier did not respond in time');
    } catch (e) {
      debugPrint('[ai] authenticate failed: $e');
      return AuthResult.error('Classifier is unreachable');
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _client.close();
    _online.close();
  }
}
