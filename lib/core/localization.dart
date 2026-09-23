import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App-owned copy only. Never pass dictated text or translation output here.
class VeyaStrings {
  final Map<String, String> messages;
  VeyaStrings(this.messages);
  // Only languages with bundled interface dictionaries are loaded here.
  // Voice translation languages remain available in core/models.dart and use
  // the English interface fallback when no dictionary is bundled.
  static const codes = ['en', 'hi', 'ml', 'ta', 'te', 'kn', 'bn', 'mr', 'gu', 'ur', 'or', 'pa'];
  static const delegate = _StringsDelegate();
  static final Map<String, VeyaStrings> _cache = {};
  static Future<void> preload() async {
    await Future.wait(
      codes.map((code) async {
        final json = await rootBundle.loadString('assets/i18n/$code.json');
        _cache[code] = VeyaStrings(
          Map<String, String>.from(jsonDecode(json) as Map),
        );
      }),
    );
  }

  String resolve(String key, [Map<String, String> args = const {}]) {
    var value = messages[key];
    // History metadata combines independently translated labels.
    value ??= key.contains(' · ')
        ? key.split(' · ').map((part) => messages[part] ?? part).join(' · ')
        : key;
    for (final entry in args.entries) {
      value = value!.replaceAll('{${entry.key}}', entry.value);
    }
    return value!;
  }
}

class _StringsDelegate extends LocalizationsDelegate<VeyaStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) =>
      VeyaStrings.codes.contains(locale.languageCode);
  @override
  Future<VeyaStrings> load(Locale locale) {
    final cached = VeyaStrings._cache[locale.languageCode];
    if (cached != null) return SynchronousFuture(cached);
    return VeyaStrings.preload().then(
      (_) => VeyaStrings._cache[locale.languageCode]!,
    );
  }

  @override
  bool shouldReload(_StringsDelegate old) => false;
}

String t(
  BuildContext context,
  String key, [
  Map<String, String> args = const {},
]) => (Localizations.of<VeyaStrings>(context, VeyaStrings) ?? VeyaStrings({}))
    .resolve(key, args);

/// A const-friendly localized label. User content uses ordinary Text widgets.
class LText extends StatelessWidget {
  final String data;
  final Map<String, String> args;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;
  final String? semanticsLabel;
  const LText(
    this.data, {
    super.key,
    this.args = const {},
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
    this.semanticsLabel,
  });
  @override
  Widget build(BuildContext context) => Text(
    t(context, data, args),
    style: style,
    textAlign: textAlign,
    overflow: overflow,
    maxLines: maxLines,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel == null ? null : t(context, semanticsLabel!),
  );
}
