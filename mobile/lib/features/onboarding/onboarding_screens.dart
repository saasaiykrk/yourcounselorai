import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/safety_content.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/surfaces.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) context.go('/welcome');
    });
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
        children: [
          const Center(child: BrandLogo(width: 290)),
          const PageHeading(
            'Think a case through, with safety built in.',
            message: 'A clinical reference and documentation aid for registered mental-health professionals.',
            hero: true,
          ),
          AppCard(
            child: Column(
              children: const [
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

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();

  bool get _valid => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

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
          FilledButton(
            onPressed: _valid ? () => context.push('/code', extra: _email.text.trim()) : null,
            child: const Text('Send code'),
          ),
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
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(hintText: 'name@clinic.in'),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CodeScreen extends StatefulWidget {
  const CodeScreen({super.key, this.email});

  final String? email;

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _length = 6;
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _resendIn = 45;

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
        actions: [
          FilledButton(
            onPressed: digits.length == _length ? () => context.go('/details') : null,
            child: const Text('Verify'),
          ),
        ],
        children: [
          PageHeading(
            'Check your email',
            message: 'Enter the 6-digit code we sent to ${widget.email ?? 'your email'}.',
          ),
          Stack(
            children: [
              // A single real text field handles typing, paste and SMS/email autofill;
              // the boxes below just display its value.
              Opacity(
                opacity: 0,
                child: TextField(
                  controller: _code,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(_length)],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Semantics(
                label: '6-digit code, ${digits.length} entered',
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: _focus.requestFocus,
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
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text("Didn't get it? Check spam.", style: AppText.smallMuted)),
              TextButton(
                onPressed: _resendIn > 0 ? null : _startCountdown,
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

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({super.key});

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  ClinicianRole _role = ClinicianRole.psychologist;
  final _registration = TextEditingController();
  bool _consent = false;

  bool get _valid => _consent && (!_role.needsRegistration || _registration.text.trim().isNotEmpty);

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
        actions: [
          FilledButton(
            onPressed: _valid ? () => context.go('/pending') : null,
            child: const Text('Submit for verification'),
          ),
        ],
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
        ],
      ),
    );
  }

  Widget _bar(Color color) => Container(
    height: 5,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
  );
}

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StatusPage(
      icon: Icons.schedule_rounded,
      tone: Tone.check,
      title: "We're verifying you",
      message:
          "We check every registration on the official register by hand. We'll email you the moment you can start.",
      actions: [
        OutlinedButton(onPressed: () => context.go('/consult'), child: const Text('Check status')),
        TextButton(onPressed: () => context.go('/welcome'), child: const Text('Sign out')),
      ],
      children: const [
        StepList(
          activeColor: AppColors.checkDot,
          steps: [
            StepItem('Details submitted', StepStatus.done, detail: 'Psychologist · RCI'),
            StepItem('Checking the register', StepStatus.active),
            StepItem('Access unlocked, email sent', StepStatus.pending),
          ],
        ),
      ],
    );
  }
}
