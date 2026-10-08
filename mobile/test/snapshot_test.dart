// CR-001 Case Snapshot form: pre-filled fields with a tick, every other field needs a value or a
// status, "Skip remaining", Risk present goes straight to the safety pathway, identifiers in typed
// text are blocked, and the completed snapshot is shown read-only before the report.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

// The same files the server sends (shared/), so the test follows any wording change.
final _defs = (jsonDecode(File('../shared/snapshot_fields.json').readAsStringSync()) as Map)['fields'] as List;
final _copy = Map<String, dynamic>.from(jsonDecode(File('../shared/ui_copy.json').readAsStringSync()) as Map)
  ..removeWhere((k, _) => k.startsWith('_'));

const _prefilled = {
  'age': ([], '34'),
  'gender': (['Female'], ''),
  'presenting_concern': ([], 'panic attacks with sweating and palpitations'),
  'duration': (['2–4 weeks'], ''),
  'onset': (['Sudden'], ''),
  'precipitant': (['None reported'], ''),
};

class _Profile implements ProfileRepository {
  @override
  Future<Me> me() async =>
      const Me(verificationStatus: 'verified', level: 'L2', role: 'psychologist', guidedConsultation: true);

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit profile) async =>
      const ProfileEditResult(verificationStatus: 'verified', reverify: false);
}

/// Behaves like the server's snapshot flow, recording every save.
class _SnapshotRepo extends PreviewConsultationRepository {
  _SnapshotRepo({this.optional = const {}}) : super(delay: Duration.zero);

  /// Fields the case check said this case does not need.
  final Set<String> optional;

  final saves = <(Map<String, SnapshotEntry>, bool, bool)>[];
  final steps = <String>[];
  final entries = <String, Map<String, dynamic>>{
    for (final e in _prefilled.entries)
      e.key: {'chips_selected': e.value.$1, 'value_text': e.value.$2, 'prefilled': true, 'resolved': true},
  };
  String stage = 'INITIAL_CASE';

  Consultation _view() => Consultation.fromJson({
    'id': 'k1',
    'stage': stage,
    'case_type': 'Adult panic attacks',
    'snapshot': {
      'fields': [
        for (final d in _defs.cast<Map<String, dynamic>>())
          {
            ...d,
            'statuses': d['statuses'] ?? const ['not_known', 'not_yet_asked', 'not_applicable'], // server default
            'optional': optional.contains(d['key']),
            'chips_selected': [],
            'value_text': '',
            'status': null,
            'prefilled': false,
            'resolved': false,
            ...?entries[d['key']],
          },
      ],
      'copy': _copy,
      'ask_next': [
        for (final d in _defs.cast<Map<String, dynamic>>())
          if (entries[d['key']]?['status'] == 'not_yet_asked' || entries[d['key']]?['status'] == 'skipped') d['label'],
      ],
    },
  });

  @override
  Future<Consultation> start({required String text, required Map<String, int> redactionCounts}) async => _view();

  @override
  Future<Consultation> updateSnapshot(
    String id,
    Map<String, SnapshotEntry> fields, {
    bool done = false,
    bool skipRemaining = false,
  }) async {
    saves.add((fields, done, skipRemaining));
    fields.forEach(
      (k, e) =>
          entries[k] = {'chips_selected': e.chips, 'value_text': e.text, 'status': e.status?.api, 'resolved': true},
    );
    if (fields['risk_screening']?.chips.contains('Risk present') ?? false) {
      stage = 'SAFETY_STOP';
      return Consultation(id: 'k1', stage: ConsultationStage.safetyStop, snapshot: _view().snapshot);
    }
    if (skipRemaining) {
      for (final d in _defs.cast<Map<String, dynamic>>()) {
        entries.putIfAbsent(d['key'] as String, () => {'status': 'skipped', 'resolved': true});
      }
    }
    if (done || skipRemaining) stage = 'INFORMATION_SUFFICIENT';
    return _view();
  }

  @override
  Future<Consultation> reply(String id, {required String action, String text = '', required String messageId}) async {
    steps.add(action);
    stage = 'INITIAL_CASE';
    return _view();
  }
}

Future<void> _open(WidgetTester tester, _SnapshotRepo repo, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Profile()),
        consultationRepositoryProvider.overrideWithValue(repo),
      ],
      child: YourCounselorApp(router: buildRouter(initialLocation: '/consult')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check & start'));
  await tester.pumpAndSettle();
  for (final yes in find.text('Yes, remove').evaluate().toList()) {
    await tester.ensureVisible(find.byWidget(yes.widget).first);
    await tester.tap(find.byWidget(yes.widget).first);
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send securely'));
  await tester.pumpAndSettle();
}

final _form = find.byKey(const ValueKey('snapshot-form'));

// The form's own list (text fields have scrollables of their own).
final _list = find.descendant(of: _form, matching: find.byType(Scrollable)).first;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: _list);
  await tester.ensureVisible(f); // to the top, clear of the button bar
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _inField(String key, Finder f) => find.descendant(of: find.byKey(ValueKey('snapshot-$key')), matching: f);

FilledButton _continue(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('snapshot-continue')));

void main() {
  testWidgets('CR1-01: the form shows what the case gave (✓) and asks for every other field', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    expect(_form, findsOneWidget, reason: 'the form comes before any question');
    expect(find.text('From your case'), findsWidgets);
    expect(_inField('age', find.text('From your case')), findsOneWidget);
    expect(find.text('${_defs.length - _prefilled.length} to go'), findsOneWidget);
    expect(_continue(tester).onPressed, isNull, reason: 'Continue stays off until every field is resolved');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('snapshot-medications')), 200, scrollable: _list);
    expect(_inField('medications', find.text('Needs an answer or a status')), findsOneWidget);
  });

  testWidgets('CR1-04: every field answered or given a status, then Continue sends the whole snapshot', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    for (final d in _defs.cast<Map<String, dynamic>>()) {
      final key = d['key'] as String;
      if (_prefilled.containsKey(key)) continue;
      final statuses = (d['statuses'] as List?) ?? const ['not_known', 'not_yet_asked', 'not_applicable'];
      if (key == 'medications') {
        await _tap(tester, _inField(key, find.widgetWithText(ChoiceChip, 'None')));
      } else if (key == 'occupation') {
        await _tap(tester, _inField(key, find.widgetWithText(ChoiceChip, 'Salaried')));
        await tester.enterText(find.byKey(const ValueKey('snapshot-text-occupation')), 'IT professional');
        await tester.pumpAndSettle();
      } else {
        final status = statuses.contains('not_yet_asked') ? 'not_yet_asked' : statuses.first;
        await _tap(tester, find.byKey(ValueKey('status-$key-$status')));
      }
    }
    expect(_continue(tester).onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('snapshot-continue')));
    await tester.pumpAndSettle();

    final (fields, done, skip) = repo.saves.single;
    expect((done, skip), (true, false));
    expect(fields.length, _defs.length);
    expect(fields['education']!.status, SnapshotStatus.notYetAsked);
    expect(fields['medications']!.chips, ['None']);
    expect(fields['occupation']!.text, 'IT professional');
    expect(fields['age']!.text, '34', reason: 'pre-filled values are sent as they are');

    // Step 6: the read-only snapshot with Edit, then Generate.
    expect(_form, findsNothing);
    expect(find.text('Not yet asked — ask in next session'), findsNothing, reason: 'only answered fields are rows');
    expect(find.textContaining('Ask in the next session: '), findsOneWidget);
    // "Help requested" was answered Not known: named once, left out of the report.
    expect(find.text('Left out of the report (not known or N/A): Help requested'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Generate report'), findsOneWidget);
    expect(find.textContaining('not provided'), findsNothing);
  });

  testWidgets('CR1-05: Skip remaining asks first, then marks the rest Skipped', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    await tester.tap(find.text('Skip remaining and generate'));
    await tester.pumpAndSettle();
    expect(
      find.text("Skipped fields will be shown as 'Skipped' and the report will be less specific."),
      findsOneWidget,
    );
    await tester.tap(find.text('Skip and continue'));
    await tester.pumpAndSettle();
    final (fields, done, skip) = repo.saves.single;
    expect(skip, isTrue);
    expect(fields.keys.toSet(), _prefilled.keys.toSet());
    expect(find.textContaining('Ask in the next session: '), findsOneWidget);
    expect(find.text('Generate report'), findsOneWidget);
  });

  testWidgets('CR1-06: Risk present shows the emergency guidance straight away, then the form again', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    await _tap(tester, _inField('risk_screening', find.widgetWithText(ChoiceChip, 'Risk present')));
    expect(repo.saves.single.$1['risk_screening']!.chips, ['Risk present']);
    expect(find.text('Safety first'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('14416'), findsWidgets);
    await tester.tap(find.text('Immediate safety is being managed — continue'));
    await tester.pumpAndSettle();
    expect(repo.steps, ['safety_managed']);
    expect(_form, findsOneWidget);
  });

  testWidgets('CR1-07: an employer name in Occupation must be replaced; an identifier blocks', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    final occupation = find.byKey(const ValueKey('snapshot-text-occupation'));
    await tester.scrollUntilVisible(occupation, 200, scrollable: _list);
    await tester.enterText(occupation, 'IT professional at Infosys');
    await tester.pumpAndSettle();
    expect(find.textContaining('Possible name or employer: Infosys'), findsOneWidget);
    expect(find.text("It's not a name — keep"), findsNothing, reason: 'Occupation has no "keep" option');
    await tester.enterText(occupation, 'call 9876543210');
    await tester.pumpAndSettle();
    expect(find.text('This looks like an identifier. Remove it before continuing.'), findsOneWidget);
    await tester.enterText(occupation, 'IT professional');
    await tester.pumpAndSettle();
    expect(find.textContaining('Possible name'), findsNothing);
    expect(find.textContaining('identifier'), findsNothing);
  });

  testWidgets('only what this case needs is required; the rest folds away as optional', (tester) async {
    const notNeeded = {'education', 'occupation', 'living_situation', 'family_structure', 'family_history'};
    final repo = _SnapshotRepo(optional: notNeeded);
    await _open(tester, repo);
    expect(find.text('${_defs.length - _prefilled.length - notNeeded.length} to go'), findsOneWidget);
    expect(find.byKey(const ValueKey('snapshot-education')), findsNothing, reason: 'folded until opened');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('snapshot-optional')), 300, scrollable: _list);
    expect(find.textContaining('More details (optional) (5)'), findsOneWidget);
    await tester.tap(find.textContaining('More details (optional)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snapshot-education')), findsOneWidget);
    expect(_inField('education', find.text('Needs an answer or a status')), findsNothing);

    // Skip the required rest: the optional fields are never sent (and so never marked Skipped).
    await tester.tap(find.text('Skip remaining and generate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip and continue'));
    await tester.pumpAndSettle();
    expect(repo.saves.single.$1.keys.toSet().intersection(notNeeded), isEmpty);
  });

  testWidgets('after Skip remaining, editing does not demand the skipped fields', (tester) async {
    final repo = _SnapshotRepo();
    await _open(tester, repo);
    await tester.tap(find.text('Skip remaining and generate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip and continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Save changes'), findsOneWidget);
    await _tap(tester, _inField('medications', find.widgetWithText(ChoiceChip, 'None')));
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save changes'));
    expect(save.onPressed, isNotNull, reason: 'skipped fields stay skipped');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repo.saves.last.$1.keys, ['medications'], reason: 'only the change is sent');
  });

  for (final size in const [Size(320, 640), Size(390, 844)]) {
    testWidgets('the form fits a ${size.width.toInt()}-wide phone', (tester) async {
      await _open(tester, _SnapshotRepo(), size: size);
      expect(tester.takeException(), isNull);
      await tester.drag(_form, const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
