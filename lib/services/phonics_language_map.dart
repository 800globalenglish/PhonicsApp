
const Map<String, int> phonicsLanguageIds = {
  'en-US': 1, // English — the base title on TradeLingo_Resources itself, not in OtherResources
  'zh-CN': 2, // Chinese (Simplified)
  'hi-IN': 3, // Hindi
  'es-ES': 4, // Spanish
  'ar-SA': 5, // Arabic
  'ko-KR': 10, // Korean
  'he-IL': 11, // Hebrew
  'ja-JP': 12, // Japanese
  'zh-HK': 13, // Chinese (Traditional)
  'de-DE': 15, // German
  'pt-PT': 16, // Portuguese
  'vi-VN': 18, // Vietnamese
  'it-IT': 23, // Italian
  'uk-UA': 25, // Ukrainian
  'th-TH': 26, // Thai
  'fr-FR': 27, // French
  'fil-PH': 28, // Filipino
  'ru-RU': 9, // Russian
};


int phonicsLanguageIdFor(String appLanguageCode) {
  return phonicsLanguageIds[appLanguageCode] ?? 1;
}
