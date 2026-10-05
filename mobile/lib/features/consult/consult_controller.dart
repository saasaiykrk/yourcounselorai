import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/content/safety_content.dart';
import '../../core/providers.dart';

/// Where a consult is. Case text and replies live only in this in-memory
/// state; nothing is written to the phone, and [ConsultController.clear]
/// wipes it (new consult, sign-out).
sealed class ConsultState {
  const ConsultState();
}

final class ConsultIdle extends ConsultState {
  const ConsultIdle();
}

final class ConsultSending extends ConsultState {
  const ConsultSending(this.mode);

  final ConsultMode mode;
}

final class ConsultReplied extends ConsultState {
  const ConsultReplied(this.reply);

  final ConsultReply reply;
}

final class ConsultFailed extends ConsultState {
  const ConsultFailed(this.error);

  final ApiException error;
}

class ConsultController extends Notifier<ConsultState> {
  String? _conversationId;
  int _request = 0;

  @override
  ConsultState build() => const ConsultIdle();

  /// The latest reply, for follow-ups and "Report a problem".
  ConsultReply? get lastReply => switch (state) {
    ConsultReplied(:final reply) => reply,
    _ => null,
  };

  /// Sends already-cleaned text. Follow-ups continue the same conversation.
  Future<void> send({
    required String text,
    required ConsultMode mode,
    required Map<String, int> redactionCounts,
  }) async {
    final request = ++_request;
    state = ConsultSending(mode);
    try {
      final reply = await ref
          .read(consultRepositoryProvider)
          .send(
            ConsultRequest(
              text: text,
              mode: mode.apiCode,
              redactionCounts: redactionCounts,
              conversationId: _conversationId,
            ),
          );
      if (request != _request) return; // cleared or superseded meanwhile
      _conversationId = reply.conversationId;
      state = ConsultReplied(reply);
    } on ApiException catch (e) {
      if (request != _request) return;
      if (e is NotFound) _conversationId = null; // conversation gone: the next send starts fresh
      state = ConsultFailed(e);
    } catch (_) {
      if (request != _request) return;
      state = const ConsultFailed(ServerProblem(null));
    }
  }

  Future<void> report({required ReportCategory category, required String note}) async {
    final reply = lastReply;
    if (reply == null) return;
    await ref.read(consultRepositoryProvider).report(turnId: reply.turnId, category: category.apiValue, note: note);
  }

  /// Shows a reply that arrived another way (a guided consultation's report) on
  /// the reply screen; a follow-up then continues that conversation.
  void showReply(ConsultReply reply) {
    _request++;
    _conversationId = reply.conversationId;
    state = ConsultReplied(reply);
  }

  /// Starts over: forgets the conversation and the last reply.
  void clear() {
    _request++;
    _conversationId = null;
    state = const ConsultIdle();
  }
}

final consultControllerProvider = NotifierProvider<ConsultController, ConsultState>(ConsultController.new);

/// Where to go once a consult finishes, and what to pass along.
(String, Object?) routeForOutcome(ConsultState state) => switch (state) {
  ConsultReplied(:final reply) when !reply.delivered => ('/held-back', null),
  ConsultReplied(:final reply) when reply.meta.isSafetyGate => ('/safety', null),
  ConsultReplied() => ('/reply', null),
  ConsultFailed(error: IdentifiersDetected(:final types)) => ('/identifiers', types),
  ConsultFailed(error: DailyLimitReached()) => ('/limit', null),
  ConsultFailed(error: Unauthorized()) => ('/sign-in', null),
  ConsultFailed(error: NotVerified()) => ('/pending', null),
  ConsultFailed(:final error) => ('/offline', error),
  ConsultIdle() || ConsultSending() => ('/consult', null),
};
