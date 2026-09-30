/// The app's data layer. Screens and controllers call these interfaces; the
/// real implementations talk to the backend, the preview ones return samples.
library;

import 'api/api_client.dart';
import 'api/api_models.dart';
import 'demo/preview_data.dart';

abstract interface class ProfileRepository {
  Future<Me> me();

  Future<void> submit(ProfileSubmission profile);
}

abstract interface class ConsultRepository {
  Future<ConsultReply> send(ConsultRequest request);

  Future<void> report({required String turnId, required String category, required String note});
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Me> me() => _api.me();

  @override
  Future<void> submit(ProfileSubmission profile) => _api.submitProfile(profile);
}

class ApiConsultRepository implements ConsultRepository {
  ApiConsultRepository(this._api);

  final ApiClient _api;

  @override
  Future<ConsultReply> send(ConsultRequest request) => _api.consult(request);

  @override
  Future<void> report({required String turnId, required String category, required String note}) =>
      _api.reportIncident(turnId: turnId, category: category, note: note);
}

/// Preview: walks through signup → pending → verified without a server.
class PreviewProfileRepository implements ProfileRepository {
  var _status = 'none';

  @override
  Future<Me> me() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final current = _status;
    // Each status check after submitting moves one step, so the pending screen can be tried.
    if (_status == 'pending') _status = 'verified';
    return Me(
      verificationStatus: current,
      level: current == 'verified' ? 'L2' : null,
      role: 'psychologist',
      registrationBody: 'RCI',
    );
  }

  @override
  Future<void> submit(ProfileSubmission profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _status = 'pending';
  }
}

/// Preview: returns the sample reply after a short "drafting" pause.
class PreviewConsultRepository implements ConsultRepository {
  PreviewConsultRepository({this.delay = const Duration(seconds: 4)});

  final Duration delay;
  var _turn = 0;

  @override
  Future<ConsultReply> send(ConsultRequest request) async {
    await Future<void>.delayed(delay);
    final risk = request.text.toLowerCase().contains(kPreviewRiskPhrase);
    _turn++;
    return ConsultReply(
      turnId: 'preview-turn-$_turn',
      conversationId: request.conversationId ?? 'preview-conversation',
      delivered: true,
      text: risk ? kPreviewSafetyMarkdown : kPreviewReplyMarkdown,
      skillVersion: '2.1.1',
      meta: ReplyMeta(mode: 'A', gate: risk ? 'gate1' : 'none', ceiling: risk ? 'NA' : 'Low', level: 'L2'),
    );
  }

  @override
  Future<void> report({required String turnId, required String category, required String note}) async {}
}
