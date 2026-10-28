import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/countries.dart';
import '../mobile_number.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// What the clinician has typed: the number as the server stores it (+919876543210), or null if it isn't
/// a valid mobile number yet; [typed] is false while the field is empty.
typedef MobileInput = ({String? value, bool typed});

/// The national digits written the usual way for the country: India "98765 43210", the US and Canada
/// "(415) 555-0132", elsewhere groups of three ("791 112 3456").
String formatNational(String digits, Country c) {
  if (c.iso == 'IN') {
    return digits.length <= 5 ? digits : '${digits.substring(0, 5)} ${digits.substring(5)}';
  }
  if (c.dial == '1') {
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '(${digits.substring(0, 3)}) ${digits.substring(3)}';
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  final groups = <String>[];
  var rest = digits;
  while (rest.length > 4) {
    groups.add(rest.substring(0, 3));
    rest = rest.substring(3);
  }
  if (rest.isNotEmpty) groups.add(rest);
  return groups.join(' ');
}

/// The number in the server's form for this country. A leading 0 (the trunk prefix, as in 098765 43210 or
/// 07911 123456) is dropped, and so is the country code typed again in front (91 98765 43210).
String? mobileValue(Country c, String text) {
  var digits = text.replaceAll(RegExp(r'\D'), '');
  digits = digits.replaceFirst(RegExp(r'^0+'), '');
  if (digits.startsWith(c.dial) && normalizeMobile('+$digits') != null && digits.length > c.dial.length + 6) {
    digits = digits.substring(c.dial.length);
  }
  if (digits.isEmpty) return null;
  final v = normalizeMobile('+${c.dial}$digits');
  return v != null && v.startsWith('+${c.dial}') ? v : null;
}

/// Mobile number with a country code picker (India first). Pasting or typing a number that starts with
/// "+" picks its country.
class MobileNumberField extends StatefulWidget {
  const MobileNumberField({super.key, this.initial, required this.onChanged, this.fieldKey});

  /// The saved number (+919876543210), shown split into country and number.
  final String? initial;
  final ValueChanged<MobileInput> onChanged;
  final Key? fieldKey;

  @override
  State<MobileNumberField> createState() => _MobileNumberFieldState();
}

class _MobileNumberFieldState extends State<MobileNumberField> {
  late Country _country;
  late final TextEditingController _number;

  @override
  void initState() {
    super.initState();
    final split = splitMobile(widget.initial);
    _country = split?.country ?? kIndia;
    _number = TextEditingController(text: split == null ? '' : formatNational(split.national, _country));
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String? get _value => mobileValue(_country, _number.text);

  void _changed() {
    final text = _number.text.trim();
    if (text.startsWith('+')) {
      final split = splitMobile('+${text.replaceAll(RegExp(r'\D'), '')}');
      if (split != null) {
        _country = split.country;
        final formatted = formatNational(split.national, _country);
        _number.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
    setState(() {});
    widget.onChanged((value: _value, typed: _number.text.trim().isNotEmpty));
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CountrySheet(),
    );
    if (picked == null || !mounted) return;
    _country = picked;
    final digits = _number.text.replaceAll(RegExp(r'\D'), '');
    _number.text = formatNational(digits, _country);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _number.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Country code ${_country.name} +${_country.dial}. Change',
          child: InkWell(
            key: const ValueKey('country-code'),
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: Text(_country.flag, style: const TextStyle(fontSize: 20))),
                  const SizedBox(width: 6),
                  Text('+${_country.dial}', style: AppText.label),
                  const Icon(Icons.arrow_drop_down_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: _number,
            maxLength: 20,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [_NationalFormatter(() => _country)],
            decoration: InputDecoration(
              hintText: _country.iso == 'IN'
                  ? '98765 43210'
                  : _country.dial == '1'
                  ? '(415) 555-0132'
                  : 'Mobile number',
              counterText: '',
              errorText: typed && _value == null
                  ? (_country.iso == 'IN'
                        ? 'A 10-digit mobile number, like 98765 43210'
                        : 'Check the mobile number for ${_country.name}')
                  : null,
            ),
            onChanged: (_) => _changed(),
          ),
        ),
      ],
    );
  }
}

/// Keeps digits only and writes them the country's way, with the cursor after the same digit. A number
/// starting with "+" is let through as typed, so the field can read its country code.
class _NationalFormatter extends TextInputFormatter {
  _NationalFormatter(this.country);

  final Country Function() country;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.trimLeft().startsWith('+')) {
      final kept = '+${text.replaceAll(RegExp(r'[^0-9]'), '')}';
      return TextEditingValue(
        text: kept,
        selection: TextSelection.collapsed(offset: kept.length),
      );
    }
    final cursor = newValue.selection.end < 0 ? text.length : newValue.selection.end;
    final digitsBefore = text.substring(0, cursor).replaceAll(RegExp(r'\D'), '').length;
    final digits = text.replaceAll(RegExp(r'\D'), '');
    final formatted = formatNational(digits.length > 15 ? digits.substring(0, 15) : digits, country());
    var offset = 0, seen = 0;
    while (offset < formatted.length && seen < digitsBefore) {
      if (RegExp(r'\d').hasMatch(formatted[offset])) seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase().replaceFirst('+', '');
    final list = kCountries
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.dial.startsWith(q) || c.iso.toLowerCase() == q)
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey('country-search'),
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Country or code'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                  title: Text(c.name),
                  trailing: Text('+${c.dial}', style: AppText.label),
                  onTap: () => Navigator.of(context).pop(c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
