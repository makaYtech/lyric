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
/// Поэтому для ЛЮБОГО запроса к домену ЭПОСа нужно использовать именно
/// этот клиент, а не голый package:http.
///
/// Не забывай вызывать client.close() после использования одного запроса
/// (см. пример в GradesService) — клиент не предназначен для переиспользования
/// между множеством параллельных запросов.
Future<http.Client> createEposHttpClient() async {
  final pemData = await rootBundle.load('assets/certs/epos_chain.pem');
  final context = SecurityContext();
  context.setTrustedCertificatesBytes(pemData.buffer.asUint8List());
  final httpClient = HttpClient(context: context);
  return IOClient(httpClient);
}
