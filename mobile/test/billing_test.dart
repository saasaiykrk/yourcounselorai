// Plans, payments and the clinician's own key in the app:
// - errors from the server (402 no credit, 424 own key failed) reach the right screen;
// - a purchase is "done" only when the SERVER says the order is paid — never on the checkout's word;
// - plans and prices on screen come from the server, not from the app;
// - the own key is sent once, never shown again, and a failure never switches to the platform key.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_counselor/core/api/api_client.dart';
import 'package:your_counselor/core/api/api_exceptions.dart';
import 'package:your_counselor/core/api/api_models.dart';
import 'package:your_counselor/core/api/billing_models.dart';
import 'package:your_counselor/core/billing/billing_repository.dart';
import 'package:your_counselor/core/billing/payment_gateway.dart';
import 'package:your_counselor/core/billing/purchase.dart';
import 'package:your_counselor/core/providers.dart';
import 'package:your_counselor/core/repositories.dart';
import 'package:your_counselor/features/consult/consult_controller.dart';
import 'package:your_counselor/main.dart';
import 'package:your_counselor/router.dart';

BillingOrder anOrder(String status, {String? reason}) =>
    BillingOrder(id: 'o1', plan: 'sub_30', status: status, amount: 199900, failureReason: reason);

const checkout = CheckoutDetails(
  key: 'rzp_test_x',
  orderId: 'order_1',
  amount: 199900,
  currency: 'INR',
  name: 'YourCounselor',
  description: 'Monthly',
);

const paid = CheckoutCompleted(orderId: 'order_1', paymentId: 'pay_1', signature: 'sig');

class FakeGateway implements PaymentGateway {
  FakeGateway(this.result, {this.supported = true});

  final CheckoutResult result;
  @override
  final bool supported;
  int opened = 0;

  @override
  Future<CheckoutResult> open(CheckoutDetails details) async {
    opened++;
    return result;
  }
}

class FakeBilling implements BillingRepository {
  FakeBilling({
    this.start = const OrderStart(BillingOrder(id: 'o1', plan: 'sub_30', status: 'created', amount: 199900), checkout),
    this.verifyResult,
    this.verifyError,
    List<BillingOrder>? polls,
    this.plansValue,
    this.statusValue = const BillingStatus(enabled: true),
  }) : polls = polls ?? [];

  OrderStart start;
  BillingOrder? verifyResult;
  ApiException? verifyError;
  List<BillingOrder> polls;
  BillingPlans? plansValue;
  BillingStatus statusValue;
  final cancelled = <String>[];
  final savedKeys = <String>[];
  String? createdPlan;

  @override
  Future<OrderStart> createOrder({required String plan, String? reportType}) async {
    createdPlan = '$plan:${reportType ?? ''}';
    return start;
  }

  @override
  Future<BillingOrder> verify(String orderId, CheckoutCompleted payment) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult!;
  }

  @override
  Future<BillingOrder> order(String orderId) async => polls.isEmpty ? anOrder('pending') : polls.removeAt(0);

  @override
  Future<void> cancelOrder(String orderId) async => cancelled.add(orderId);

  @override
  Future<BillingPlans> plans() async => plansValue!;

  @override
  Future<BillingStatus> status() async => statusValue;

  @override
  Future<List<BillingOrder>> orders() async => const [];

  @override
  Future<List<LedgerEntry>> ledger() async => const [];

  @override
  Future<OwnKeyCheck> saveOwnKey(String apiKey) async {
    savedKeys.add(apiKey);
    statusValue = const BillingStatus(
      enabled: true,
      ownKey: OwnKeyStatus(
        available: true,
        connected: true,
        status: 'valid',
        last4: 'AbCd',
        reportTypes: ['guided', 'direct'],
      ),
    );
    return const OwnKeyCheck(connected: true, status: 'valid', last4: 'AbCd');
  }

  @override
  Future<OwnKeyCheck> checkOwnKey() async => const OwnKeyCheck(connected: true, status: 'valid', last4: 'AbCd');

  @override
  Future<void> removeOwnKey() async {}
}

class Verified implements ProfileRepository {
  @override
  Future<Me> me() async => const Me(verificationStatus: 'verified', level: 'L2', role: 'psychologist', pricing: true);

  @override
  Future<void> submit(ProfileSubmission profile) async {}

  @override
  Future<ProfileEditResult> edit(ProfileEdit profile) async =>
      const ProfileEditResult(verificationStatus: 'verified', reverify: false);
}

PurchaseFlow flow(FakeBilling repo, PaymentGateway gw) =>
    PurchaseFlow(repo, gw, pollEvery: Duration.zero, pollTimes: 3);

Widget app(FakeBilling repo, String at, {List overrides = const []}) => ProviderScope(
  overrides: [
    profileRepositoryProvider.overrideWithValue(Verified()),
    billingRepositoryProvider.overrideWithValue(repo),
    paymentGatewayProvider.overrideWithValue(FakeGateway(const CheckoutCancelled())),
    ...overrides,
  ],
  child: YourCounselorApp(router: buildRouter(initialLocation: at)),
);

void main() {
  group('server errors', () {
    test('402 → PaymentRequired with the server price', () {
      final e = mapStatus(402, {
        'detail': {
          'error': 'payment_required',
          'report_type': 'guided',
          'price': 19900,
          'currency': 'INR',
          'message': 'No credits.',
        },
      });
      expect(
        e,
        isA<PaymentRequired>().having((p) => p.price, 'price', 19900).having((p) => p.reportType, 'type', 'guided'),
      );
    });

    test('424 → OwnKeyFailed, not a generic error', () {
      final e = mapStatus(424, {
        'detail': {
          'error': 'byok_failed',
          'code': 'invalid_key',
          'message': 'Anthropic did not accept this API key.',
          'retry': false,
        },
      });
      expect(e, isA<OwnKeyFailed>().having((k) => k.code, 'code', 'invalid_key'));
    });

    test('a refusal with a message keeps the message; identifiers stay identifiers', () {
      expect(
        mapStatus(409, {
          'detail': {'error': 'not_purchasable', 'message': 'This plan is not on sale.'},
        }),
        isA<BillingRefused>().having((b) => b.message, 'message', 'This plan is not on sale.'),
      );
      expect(
        mapStatus(422, {
          'detail': {
            'error': 'identifiers_detected',
            'types': ['PHONE'],
          },
        }),
        isA<IdentifiersDetected>(),
      );
      expect(mapStatus(409, {'detail': 'busy'}), isA<Conflict>());
    });

    test('no credit or a failed own key opens the explanation screen', () {
      expect(routeForOutcome(const ConsultFailed(PaymentRequired(message: 'x'))).$1, '/no-credit');
      expect(routeForOutcome(const ConsultFailed(OwnKeyFailed(code: 'invalid_key', message: 'x'))).$1, '/no-credit');
    });
  });

  test('money is shown in rupees with Indian grouping', () {
    expect(formatMoney(199900), '₹1,999');
    expect(formatMoney(10000000), '₹1,00,000');
    expect(formatMoney(19950), '₹199.50');
    expect(formatMoney(0), '₹0');
  });

  test('a consult request carries its retry id and the own-key choice', () {
    const r = ConsultRequest(text: 't', mode: 'B', redactionCounts: {}, requestId: 'abc12345', useOwnKey: true);
    expect(r.toJson(), containsPair('request_id', 'abc12345'));
    expect(r.toJson(), containsPair('use_own_key', true));
    expect(
      const ConsultRequest(text: 't', mode: 'B', redactionCounts: {}).toJson().containsKey('use_own_key'),
      isFalse,
    );
  });

  group('purchase', () {
    test('done only when the server confirms the payment', () async {
      final repo = FakeBilling(verifyResult: anOrder('paid'));
      final out = await flow(repo, FakeGateway(paid)).buy(plan: 'sub_30');
      expect(out, isA<PurchaseDone>());
      expect(repo.createdPlan, 'sub_30:');
    });

    test('the checkout saying "success" is not enough: a refused signature is a failure', () async {
      final repo = FakeBilling(
        verifyError: const BillingRefused(code: 'invalid_signature', message: 'This payment could not be verified.'),
      );
      final out = await flow(repo, FakeGateway(paid)).buy(plan: 'sub_30');
      expect(out, isA<PurchaseFailed>().having((f) => f.message, 'message', 'This payment could not be verified.'));
    });

    test('a payment still confirming is polled, then shown as pending — never as paid', () async {
      final later = FakeBilling(verifyResult: anOrder('pending'), polls: [anOrder('pending'), anOrder('paid')]);
      expect(await flow(later, FakeGateway(paid)).buy(plan: 'sub_30'), isA<PurchaseDone>());
      final slow = FakeBilling(verifyResult: anOrder('pending'));
      expect(await flow(slow, FakeGateway(paid)).buy(plan: 'sub_30'), isA<PurchasePending>());
      final failed = FakeBilling(verifyResult: anOrder('failed', reason: 'card declined'));
      expect(await flow(failed, FakeGateway(paid)).buy(plan: 'sub_30'), isA<PurchaseFailed>());
    });

    test('server unreachable after checkout → pending (the server still hears from Razorpay)', () async {
      final repo = FakeBilling(verifyError: const NetworkProblem());
      expect(await flow(repo, FakeGateway(paid)).buy(plan: 'sub_30'), isA<PurchasePending>());
    });

    test('closing the checkout cancels the order', () async {
      final repo = FakeBilling();
      expect(await flow(repo, FakeGateway(const CheckoutCancelled())).buy(plan: 'sub_30'), isA<PurchaseCancelled>());
      expect(repo.cancelled, ['o1']);
    });

    test('where payments cannot run, nothing is opened and the order is cancelled', () async {
      final repo = FakeBilling();
      final gw = FakeGateway(paid, supported: false);
      expect(await flow(repo, gw).buy(plan: 'sub_30'), isA<PurchaseFailed>());
      expect(gw.opened, 0);
      expect(repo.cancelled, ['o1']);
    });

    test('a free plan granted by the server opens no checkout', () async {
      final repo = FakeBilling(
        start: const OrderStart(BillingOrder(id: 'o2', plan: 'sub_30', status: 'paid', amount: 0), null),
      );
      final gw = FakeGateway(paid);
      expect(await flow(repo, gw).buy(plan: 'sub_30'), isA<PurchaseDone>());
      expect(gw.opened, 0);
    });
  });

  group('screens', () {
    final plans = BillingPlans(
      enabled: true,
      paymentsAvailable: true,
      plans: [
        const PlanOffer(
          id: 'per_report',
          kind: 'per_report',
          name: 'Pay per report',
          prices: {'guided': 24900, 'direct': 9900},
        ),
        const PlanOffer(
          id: 'sub_50',
          kind: 'subscription',
          name: 'Clinic 50',
          price: 349900,
          reports: 50,
          durationDays: 30,
        ),
      ],
    );

    testWidgets('plans and prices come from the server', (tester) async {
      final repo = FakeBilling(
        plansValue: plans,
        statusValue: const BillingStatus(enabled: true, guidedCredits: 3, directCredits: 3),
      );
      await tester.pumpWidget(app(repo, '/pricing'));
      await tester.pumpAndSettle();
      expect(find.text('Clinic 50'), findsOneWidget);
      expect(find.text('Buy for ₹3,499'), findsOneWidget);
      expect(find.text('Guided report · ₹249'), findsOneWidget);
      expect(find.text('Monthly · 30 reports'), findsNothing, reason: 'a plan the server does not list is not shown');
      expect(find.text('3'), findsNWidgets(2));
    });

    testWidgets('pricing off: reports are free, nothing to buy', (tester) async {
      final repo = FakeBilling(
        plansValue: const BillingPlans(enabled: false),
        statusValue: const BillingStatus(enabled: false),
      );
      await tester.pumpWidget(app(repo, '/pricing'));
      await tester.pumpAndSettle();
      expect(find.text('Reports are free right now'), findsOneWidget);
      expect(find.textContaining('Buy for'), findsNothing);
    });

    testWidgets('own key: sent once, field cleared, only the last 4 shown, switch turns it on', (tester) async {
      final repo = FakeBilling(
        plansValue: plans,
        statusValue: const BillingStatus(
          enabled: true,
          ownKey: OwnKeyStatus(available: true, reportTypes: ['guided', 'direct']),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(Verified()),
          billingRepositoryProvider.overrideWithValue(repo),
          paymentGatewayProvider.overrideWithValue(FakeGateway(const CheckoutCancelled())),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: YourCounselorApp(router: buildRouter(initialLocation: '/pricing/own-key')),
        ),
      );
      await tester.pumpAndSettle();
      const key = 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789-AbCd';
      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.text('Check and save'));
      await tester.pumpAndSettle();
      expect(repo.savedKeys, [key]);
      expect(find.text('Key ending …AbCd'), findsOneWidget);
      expect(find.textContaining('abcdefghij'), findsNothing, reason: 'the key is never shown again');
      expect(find.byType(TextField), findsNothing);
      expect(container.read(useOwnKeyProvider), isFalse, reason: 'never on without the clinician choosing it');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(container.read(useOwnKeyProvider), isTrue);
    });

    testWidgets('own key failed: "write without my key" is the clinician\'s choice, not automatic', (tester) async {
      final repo = FakeBilling(plansValue: plans);
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(Verified()),
          billingRepositoryProvider.overrideWithValue(repo),
          consultRepositoryProvider.overrideWithValue(PreviewConsultRepository()),
        ],
      );
      addTearDown(container.dispose);
      container.read(useOwnKeyProvider.notifier).set(true);
      final router = buildRouter(initialLocation: '/consult');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: YourCounselorApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        router.push(
          '/no-credit',
          extra: const OwnKeyFailed(code: 'invalid_key', message: 'Anthropic did not accept this API key.'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Your Anthropic key couldn't be used"), findsOneWidget);
      expect(container.read(useOwnKeyProvider), isTrue, reason: 'still the clinician\'s own key until they decide');
      await tester.tap(find.text('Write without my key'));
      await tester.pumpAndSettle();
      expect(container.read(useOwnKeyProvider), isFalse);
    });
  });
}
