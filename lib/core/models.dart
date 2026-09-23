class VoiceLanguage {
  final String name, native, code;
  const VoiceLanguage(this.name, this.native, this.code);
}

const languages = [
  VoiceLanguage('English', 'English', 'en-IN'),
  VoiceLanguage('Assamese', 'অসমীয়া', 'as-IN'),
  VoiceLanguage('Bengali', 'বাংলা', 'bn-IN'),
  VoiceLanguage('Gujarati', 'ગુજરાતી', 'gu-IN'),
  VoiceLanguage('Hindi', 'हिन्दी', 'hi-IN'),
  VoiceLanguage('Kannada', 'ಕನ್ನಡ', 'kn-IN'),
  VoiceLanguage('Malayalam', 'മലയാളം', 'ml-IN'),
  VoiceLanguage('Marathi', 'मराठी', 'mr-IN'),
  VoiceLanguage('Nepali', 'नेपाली', 'ne-IN'),
  VoiceLanguage('Punjabi', 'ਪੰਜਾਬੀ', 'pa-IN'),
  VoiceLanguage('Tamil', 'தமிழ்', 'ta-IN'),
  VoiceLanguage('Telugu', 'తెలుగు', 'te-IN'),
  VoiceLanguage('Urdu', 'اردو', 'ur-IN'),
];
