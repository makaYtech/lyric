/// Реестр возможных источников данных («endpoint service»).
///
/// Пока реально работает только ЭПОС. «Моя школа» помечена
/// unavailable — в настройках она показывается, но выбрать её нельзя,
/// пока не появятся доступы и мы не реализуем auth/endpoints под неё.
///
/// Когда появится доступ:
///   1. Снять available: false.
///   2. Дописать auth-флоу (скорее всего OAuth, не WebView с куками).
///   3. Сделать свой набор endpoints и, возможно, свои модели — у
///      «Моей школы» ответы почти наверняка другой формы.
class BackendInfo {
  final String id;
  final String displayName;
  final String description;
  final bool available;

  const BackendInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.available,
  });
}

class Backends {
  Backends._();

  static const epos = 'epos';
  static const mySchool = 'my_school';

  static const all = <BackendInfo>[
    BackendInfo(
      id: epos,
      displayName: 'ЭПОС',
      description: 'Пермский край. Текущий источник данных приложения.',
      available: true,
    ),
    BackendInfo(
      id: mySchool,
      displayName: 'Моя школа',
      description: 'Федеральная «Моя школа» (edu.gosuslugi.ru). '
          'Вход через Госуслуги.',
      available: true,
    ),
  ];

  static BackendInfo byId(String id) => all.firstWhere(
        (b) => b.id == id,
    orElse: () => all.first,
  );
}