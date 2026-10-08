import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/providers.dart';
import '../../core/repositories.dart';

/// The guided consultation on screen. The server holds the compact state; the
/// phone keeps only this in memory (never on disk) and wipes it with [clear].
class GuidedState {
  const GuidedState({this.consultation, this.caseText, this.busy = false, this.generating = false, this.error});

  final Consultation? consultation;

  /// The cleaned case as sent, shown as the first message (memory only).
  final String? caseText;

  /// A step is being processed: inputs are disabled so nothing is sent twice.
  final bool busy;

  /// The report is being written.
  final bool generating;

  /// The last failure, shown in place; the clinician can retry.
  final ApiException? error;

  GuidedState copyWith({
    Consultation? consultation,
    String? caseText,
    bool? busy,
    bool? generating,
    ApiException? error,
    bool clearError = false,
  }) => GuidedState(
    consultation: consultation ?? this.consultation,
    caseText: caseText ?? this.caseText,
    busy: busy ?? this.busy,
    generating: generating ?? this.generating,
    error: clearError ? null : error ?? this.error,
  );
}

class ConsultationController extends Notifier<GuidedState> {
  final _random = Random.secure();
  int _generation = 0;
  (String, String, String)? _lastStep; // action, text, message id — for "Try again"

  @override
  GuidedState build() => const GuidedState();

  String _messageId() => '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

  /// Runs one server step; ignores taps while another is in flight.
  Future<bool> _run(Future<Consultation> Function() step) async {
    if (state.busy) return false;
    final generation = _generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final c = await step();
      if (generation != _generation) return false;
      state = state.copyWith(consultation: c, busy: false);
      return true;
    } on ApiException catch (e) {
      if (generation != _generation) return false;
      state = state.copyWith(busy: false, error: e);
      return false;
    } catch (_) {
      if (generation != _generation) return false;
      state = state.copyWith(busy: false, error: const ServerProblem(null));
      return false;
    }
  }

  ConsultationRepository get _repo => ref.read(consultationRepositoryProvider);

  /// Starts with already-cleaned case text.
  Future<bool> start({required String text, required Map<String, int> redactionCounts}) {
    clear();
    state = GuidedState(caseText: text);
    return _run(() => _repo.start(text: text, redactionCounts: redactionCounts));
  }

  /// Opens an unfinished consultation from the server.
  Future<bool> resume(String id) {
    clear();
    return _run(() => _repo.get(id));
  }

  Future<bool> _step(String action, [String text = '']) {
    final c = state.consultation;
    if (c == null) return Future.value(false);
    final id = _messageId();
    _lastStep = (action, text, id);
    return _run(() => _repo.reply(c.id, action: action, text: text, messageId: id));
  }

  /// [text] must already be cleaned on the phone.
  Future<bool> answer(String text) => _step('answer', text);

  Future<bool> dontKnow() => _step('dont_know');

  Future<bool> skip() => _step('skip');

  /// "Generate report now": stop asking and move to ready.
  Future<bool> finish() => _step('finish');

  /// After the safety pathway: [managed] = immediate safety is being managed;
  /// otherwise risk was screened and is absent.
  Future<bool> confirmSafety({required bool managed}) => _step(managed ? 'safety_managed' : 'safety_absent');

  /// Sends the failed step again with the same message id, so it is never done twice.
  Future<bool> retry() {
    final c = state.consultation;
    final last = _lastStep;
    if (c == null || last == null) return Future.value(false);
    final (action, text, id) = last;
    return _run(() => _repo.reply(c.id, action: action, text: text, messageId: id));
  }

  /// Corrects one fact (null or empty removes it). [value] must already be cleaned.
  Future<bool> editFact(String field, String? value) {
    final c = state.consultation;
    if (c == null) return Future.value(false);
    return _run(() => _repo.editFacts(c.id, {field: value}));
  }

  /// Case Snapshot form: saves [fields] (text already cleaned on the phone). [done] moves on to the
  /// case-specific questions; [skipRemaining] marks every empty field Skipped and goes to the report.
  Future<bool> saveSnapshot(Map<String, SnapshotEntry> fields, {bool done = false, bool skipRemaining = false}) {
    final c = state.consultation;
    if (c == null) return Future.value(false);
    return _run(() => _repo.updateSnapshot(c.id, fields, done: done, skipRemaining: skipRemaining));
  }

  /// Writes the report. Returns it, or null on failure (the error is in [state]).
  Future<ConsultReply?> generateReport({bool force = false}) async {
    final c = state.consultation;
    if (c == null || state.busy) return null;
    final generation = _generation;
    state = state.copyWith(busy: true, generating: true, clearError: true);
    try {
      final (next, reply) = await _repo.report(c.id, force: force);
      if (generation != _generation) return null;
      state = state.copyWith(consultation: next, busy: false, generating: false);
      return reply;
    } on ApiException catch (e) {
      if (generation != _generation) return null;
      state = state.copyWith(busy: false, generating: false, error: e);
      return null;
    } catch (_) {
      if (generation != _generation) return null;
      state = state.copyWith(busy: false, generating: false, error: const ServerProblem(null));
      return null;
    }
  }

  /// Forgets everything on the phone (sign-out, new consultation). The server keeps
  /// the de-identified consultation so it can be continued from the Consult tab.
  void clear() {
    _generation++;
    _lastStep = null;
    state = const GuidedState();
  }
}

/// Route extra for `/consultation`: open the Case Snapshot form for editing.
const kEditSnapshot = 'edit-snapshot';

final consultationControllerProvider = NotifierProvider<ConsultationController, GuidedState>(
  ConsultationController.new,
);

/// Unfinished consultations for the "Continue" list. Re-read with `ref.invalidate`.
final openConsultationsProvider = FutureProvider.autoDispose<List<ConsultationSummary>>(
  (ref) => ref.watch(consultationRepositoryProvider).open(),
);
