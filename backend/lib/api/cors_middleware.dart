import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// CORS headers for Flutter web demo.
Middleware corsMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

/// Optional artificial latency before handling requests.
Middleware latencyMiddleware() {
  final ms = int.tryParse(Platform.environment['DEMO_LATENCY_MS'] ?? '0') ?? 0;
  if (ms <= 0) {
    return (Handler inner) => inner;
  }
  final delay = Duration(milliseconds: ms);
  return (Handler inner) {
    return (Request request) async {
      await Future<void>.delayed(delay);
      return inner(request);
    };
  };
}
