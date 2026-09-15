import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Единая точка создания http.Client, который доверяет цепочке
/// сертификатов edu-epos.permkrai.ru.
///
/// Dart использует свой собственный список доверенных корневых
/// сертификатов, отдельный от системного (Android WebView эту цепочку
/// видит нормально, а обычный http.get() — нет, падает на TLS-хендшейке).
///
/// Таймауты обязательны: без них зависший коннект висит до таймаута ОС
/// (минуты), и экран показывает вечный спиннер вместо ошибки.
Future<http.Client> createEposHttpClient() async {
  final pemData = await rootBundle.load('assets/certs/epos_chain.pem');
  final context = SecurityContext();
  context.setTrustedCertificatesBytes(pemData.buffer.asUint8List());
  final httpClient = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 10);
  return IOClient(httpClient);
}