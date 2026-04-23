import 'dart:convert';

import '../constants/app_environment.dart';
import 'app_log.dart';
import 'biz_log_tag.dart';

void logBuyRequest({
  required String method,
  required String path,
  Object? requestBody,
}) {
  AppLog.instance.info(
    jsonEncode({
      'event': 'request',
      'method': method,
      'url': '${AppEnvironment.apiServerUrl}$path',
      'request_body': requestBody,
    }),
    tag: BizLogTag.buy.tag,
  );
}

void logBuyResponse({
  required String endpoint,
  required int statusCode,
  required String responseBody,
}) {
  AppLog.instance.info(
    jsonEncode({
      'event': 'response',
      'status_code': statusCode,
      'response_body': _decodeBodyForLog(responseBody),
      'endpoint': endpoint,
    }),
    tag: BizLogTag.buy.tag,
  );
}

void logBuyInfo(String event, Map<String, dynamic> payload) {
  AppLog.instance.info(
    jsonEncode({'event': event, ...payload}),
    tag: BizLogTag.buy.tag,
  );
}

void logBuyIapRequest({
  required String action,
  Map<String, dynamic>? payload,
}) {
  AppLog.instance.info(
    jsonEncode({'event': 'iap_req', 'action': action, ...?payload}),
    tag: BizLogTag.buy.tag,
  );
}

void logBuyIapResponse({
  required String action,
  Map<String, dynamic>? payload,
}) {
  AppLog.instance.info(
    jsonEncode({'event': 'iap_resp', 'action': action, ...?payload}),
    tag: BizLogTag.buy.tag,
  );
}

Object? _decodeBodyForLog(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return body;
  }
}
