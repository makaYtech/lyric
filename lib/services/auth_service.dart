/// Токены для запросов к API ЭПОСа. Используются во всех
/// репозиториях и ApiClient. Живут «внутри» EposSession.
class EposTokens {
  final String authToken;
  final String profileId;

  EposTokens({required this.authToken, required this.profileId});
}