import 'package:flutter/services.dart';

/// Rebuilds [input] from Unicode scalar values so unpaired UTF-16 surrogates
/// cannot reach Flutter's text painter (`string is not well-formed UTF-16`).
String sanitizeUtf16(String input) {
  if (input.isEmpty) return input;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= input.length) {
        return String.fromCharCodes(input.runes);
      }
      final next = input.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) {
        return String.fromCharCodes(input.runes);
      }
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return String.fromCharCodes(input.runes);
    }
  }
  return input;
}

/// First Unicode scalar for A–Z section headers (safe for emoji names).
/// Prefer this over `name[0]`, which can split a surrogate pair.
String sectionLetterForName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '#';
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

/// Drops unpaired surrogates as the user types / pastes into a [TextField].
class Utf16SanitizingFormatter extends TextInputFormatter {
  const Utf16SanitizingFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sanitized = sanitizeUtf16(newValue.text);
    if (identical(sanitized, newValue.text) || sanitized == newValue.text) {
      return newValue;
    }
    final offset = newValue.selection.extentOffset.clamp(0, sanitized.length);
    return TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}
