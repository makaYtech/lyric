import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Сырой HttpClient с прибитой цепочкой сертификатов edu-epos.
///
/// Нужен там, где важен доступ к НЕСКОЛЬКИМ Set-Cookie в одном ответе:
/// пакет http схлопывает их в одну строку через запятую, а обмен
/// device-token → cookie-сессия как раз читает их по отдельности
/// (auth_token, profile_id, long_token, aid).
///
/// Dart использует собственный список доверенных корневых сертификатов,
/// отдельный от системного (Android WebView эту цепочку видит нормально,
/// а обычный http.get() — нет, падает на TLS-хендшейке).
Future<HttpClient> createEposRawHttpClient() async {
  final pemData = await rootBundle.load('assets/certs/epos_chain.pem');
  final context = SecurityContext();
  context.setTrustedCertificatesBytes(pemData.buffer.asUint8List());
  return HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 10);
}

/// Обёртка над createEposRawHttpClient() для тех мест, где нужен
/// обычный http.Client (ApiClient, AttachmentService и т.п.).
Future<http.Client> createEposHttpClient() async =>
    IOClient(await createEposRawHttpClient());