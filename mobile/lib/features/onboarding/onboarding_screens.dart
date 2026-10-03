import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/api_models.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config.dart';
import '../../core/content/safety_content.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

/// Where a signed-in clinician belongs, from their server-side profile.
String routeForProfile(Me me) {
  if (me.needsProfile) return '/details';
  if (me.isVerified) return '/consult';
  return '/pending';
}

String _messageFor(Object error) => switch (error) {
  AuthFailure(:final message) => message,
  NetworkProblem() => "Couldn't reach Your Counselor. Check your connection and try again.",
  _ => 'Something went wrong. Please try again. (${error.runtimeType})',
};

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1400), _route);
  }

  Future<void> _route() async {
    final auth = ref.read(authServiceProvider);
    var next = '/welcome';
    if (auth.isSignedIn) {
      try {
        next = routeForProfile(await ref.read(profileRepositoryProvider).me());
      } on Unauthorized {
        await auth.signOut();
      } catch (_) {
        next = '/consult'; // offline at launch: the consult screen will surface the error on send
      }
    }
    if (mounted) context.go(next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: BrandLogo(width: 300)),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        gap: 22,
        actions: [
          FilledButton(onPressed: () => context.push('/sign-in'), child: const Text('Get started')),
          const Text(
            'For registered professionals only. Not for clients or the public.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
        ],
        children: const [
          Center(child: BrandLogo(width: 290)),
          PageHeading(
            'Think a case through, with safety built in.',
            message: 'A clinical reference and documentation aid for registered mental-health professionals.',
            hero: true,
          ),
          AppCard(
            child: Column(
              children: [
                _Promise(
                  icon: Icons.lock_outline_rounded,
                  title: 'Client identities stay on your phone.',
                  text: ' Names and numbers are removed before anything is sent.',
                ),
                SizedBox(height: 16),
                _Promise(
                  icon: Icons.verified_user_outlined,
                  title: 'Every reply is safety-checked',
                  text: ' before you see it.',
                ),
                SizedBox(height: 16),
                _Promise(
                  icon: Icons.person_outline_rounded,
                  title: 'Reviewed by a registered clinical psychologist.',
                  text: ' Supports your judgement; never replaces it.',
                  pink: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.title, required this.text, this.pink = false});

  final IconData icon;
  final String title;
  final String text;
  final bool pink;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: pink ? AppColors.pinkTint : AppColors.lavender,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: pink ? AppColors.berry : AppColors.royalPurple),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
            style: AppText.small,
          ),
        ),
      ],
    );
  }
}

/// A primary button that shows a spinner while [onPressed] runs.
class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
          : Text(label),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Text(
        message!,
        style: const TextStyle(fontSize: 14, color: AppColors.crisis, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _valid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _send() async {
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).requestCode(email);
      if (mounted) context.push('/code', extra: email);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        gap: 24,
        actions: [
          _BusyButton(label: 'Send code', busy: _busy, onPressed: _valid ? _send : null),
          const Text(
            'By continuing you agree to the Clinician Terms.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
        ],
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: BrandMark(size: 72, semanticLabel: 'Your Counselor'),
          ),
          const PageHeading('Sign in', message: "We'll email you a 6-digit code. No password to remember."),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Work email', style: AppText.label),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: 'name@clinic.in'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _valid && !_busy ? _send() : null,
              ),
              const SizedBox(height: 8),
              _ErrorText(_error),
            ],
          ),
        ],
      ),
    );
  }
}

class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  static const _length = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _resendIn = 45;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _resendIn = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      setState(() => _resendIn--);
    });
  }

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null) return;
    _startCountdown();
    try {
      await ref.read(authServiceProvider).requestCode(email);
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    }
  }

  Future<void> _verify() async {
    final email = widget.email;
    if (email == null) {
      context.go('/sign-in');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyCode(email, _code.text);
      ref.invalidate(meProvider);
      final me = await ref.read(profileRepositoryProvider).me();
      if (mounted) context.go(routeForProfile(me));
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = _code.text;
    return Scaffold(
      appBar: AppBar(),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        gap: 24,
        actions: [_BusyButton(label: 'Verify', busy: _busy, onPressed: digits.length == _length ? _verify : null)],
        children: [
          PageHeading(
            'Check your email',
            message: 'Enter the 6-digit code we sent to ${widget.email ?? 'your email'}.',
          ),
          Stack(
            children: [
              // The boxes only display the value; screen readers skip them.
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < _length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _CodeBox(digit: i < digits.length ? digits[i] : '', active: i == digits.length),
                      ),
                    ],
                  ],
                ),
              ),
              // One real, invisible text field on top takes taps, typing, paste and
              // email-code autofill, and is what screen readers announce.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: TextField(
                    controller: _code,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_length),
                    ],
                    decoration: const InputDecoration(labelText: '6-digit code', border: InputBorder.none),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
          _ErrorText(_error),
          Row(
            children: [
              const Expanded(child: Text("Didn't get it? Check spam.", style: AppText.smallMuted)),
              TextButton(
                onPressed: _resendIn > 0 ? null : _resend,
                child: Text(_resendIn > 0 ? 'Resend in 0:${_resendIn.toString().padLeft(2, '0')}' : 'Resend code'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.digit, required this.active});

  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? AppColors.royalPurple : AppColors.inputBorder, width: active ? 2 : 1.5),
        boxShadow: active ? const [BoxShadow(color: AppColors.lavender, spreadRadius: 4)] : null,
      ),
      child: Text(
        digit,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
    );
  }
}

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  ClinicianRole _role = ClinicianRole.psychologist;
  final _registration = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _error;

  bool get _valid => _consent && (!_role.needsRegistration || _registration.text.trim().isNotEmpty);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .submit(
            ProfileSubmission(
              role: _role.apiValue,
              registrationBody: _role.registrationBody,
              registrationNumber: _role.needsRegistration ? _registration.text.trim() : null,
              consentVersion: AppConfig.consentVersion,
            ),
          );
      ref.invalidate(meProvider);
      if (mounted) context.go('/pending');
    } catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        actions: [_BusyButton(label: 'Submit for verification', busy: _busy, onPressed: _valid ? _submit : null)],
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _bar(AppColors.royalPurple)),
                  const SizedBox(width: 6),
                  Expanded(child: _bar(AppColors.line)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Step 1 of 2 · Your registration', style: AppText.overline),
            ],
          ),
          const PageHeading(
            'Your professional details',
            message: 'Your registration decides how the assistant writes for you. We verify it before you start.',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('I am a', style: AppText.label),
              const SizedBox(height: 8),
              for (final role in ClinicianRole.values) ...[
                ChoiceCard(
                  title: role.label,
                  subtitle: role.detail,
                  selected: _role == role,
                  onTap: () => setState(() => _role = role),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
          if (_role.needsRegistration)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_role.registrationBody} registration number', style: AppText.label),
                const SizedBox(height: 8),
                TextField(
                  controller: _registration,
                  maxLength: 40,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'As shown on the register', counterText: ''),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I accept the Clinician Terms and Data Processing Agreement, including that de-identified text '
              'is processed by an AI provider outside India.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
          _ErrorText(_error),
        ],
      ),
    );
  }

  Widget _bar(Color color) => Container(
    height: 5,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
  );
}

class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      ref.invalidate(meProvider);
      final me = await ref.read(meProvider.future);
      if (!mounted) return;
      if (me.isVerified) {
        context.go('/consult');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(me.isRejected ? 'We could not verify this registration.' : 'Still being checked.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final rejected = ref.watch(meProvider).value?.isRejected ?? false;
    return StatusPage(
      icon: rejected ? Icons.error_outline_rounded : Icons.schedule_rounded,
      tone: Tone.check,
      title: rejected ? "We couldn't verify you" : "We're verifying you",
      message: rejected
          ? 'The registration number did not match the official register. Contact the Your Counselor team to fix it.'
          : "We check every registration on the official register by hand. We'll email you the moment you can start.",
      actions: [
        OutlinedButton(
          onPressed: _busy ? null : _check,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Check status'),
        ),
        TextButton(onPressed: _signOut, child: const Text('Sign out')),
      ],
      children: [
        StepList(
          activeColor: AppColors.checkDot,
          steps: [
            const StepItem('Details submitted', StepStatus.done),
            StepItem('Checking the register', rejected ? StepStatus.done : StepStatus.active),
            const StepItem('Access unlocked, email sent', StepStatus.pending),
          ],
        ),
      ],
    );
  }
}
