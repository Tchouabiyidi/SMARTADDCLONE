import 'package:flutter/material.dart';

import '../services/smartads_api.dart';
import '../theme.dart';
import '../utils/formatting.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.onSignedIn});
  final SmartAdsApi api;
  final ValueChanged<Map<String, dynamic>> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool createAccount = false;
  bool obscure = true;
  bool busy = false;
  String role = 'advertiser';
  String? selectedQuickRole;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void _selectQuickAccount({
    required String accountRole,
    required String accountEmail,
    required String accountPassword,
    bool autoSubmit = false,
  }) {
    setState(() {
      createAccount = false;
      selectedQuickRole = accountRole;
      email.text = accountEmail;
      password.text = accountPassword;
    });

    if (autoSubmit && !busy) {
      submit();
    }
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.post(
        createAccount ? '/api/auth/signup' : '/api/auth/login',
        body: {
          if (createAccount) 'name': name.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          if (createAccount) 'role': role,
        },
      );
      widget.onSignedIn(result);
    } catch (error) {
      if (mounted) showMessage(context, cleanError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: _brandPanel()),
                      const SizedBox(width: 48),
                      Expanded(child: _formPanel())
                    ])
                  : Column(children: [
                      const SizedBox(height: 18),
                      _compactBrand(),
                      const SizedBox(height: 24),
                      _formPanel()
                    ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactBrand() => Column(children: [
        Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
                color: teal, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 42)),
        const SizedBox(height: 12),
        const Text('SMARTADS',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: ink,
                letterSpacing: 2)),
      ]);

  Widget _brandPanel() => Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF18394A), Color(0xFF102431)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: teal, borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 32)),
            const SizedBox(width: 12),
            const Text('SMARTADS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5))
          ]),
          const SizedBox(height: 36),
          const Text('Make every\nlocation count.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1)),
          const SizedBox(height: 16),
          const Text(
              'A modern platform to book digital billboards and broadcast your message seamlessly.',
              style: TextStyle(
                  color: Color(0xFFC0D1D6), height: 1.55, fontSize: 15)),
          const SizedBox(height: 28),
          const _FeatureRow(
              icon: Icons.location_on_outlined,
              text: 'Discover verified billboard locations'),
          const SizedBox(height: 12),
          const _FeatureRow(
              icon: Icons.calendar_month_outlined,
              text: 'Book flexible, real-time time slots'),
          const SizedBox(height: 12),
          const _FeatureRow(
              icon: Icons.auto_awesome_outlined,
              text: 'AI-assisted video review & scheduling'),
          const SizedBox(height: 12),
          const _FeatureRow(
              icon: Icons.tv_rounded,
              text: 'Automated Android TV sync & playback'),
          const SizedBox(height: 36),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, color: Color(0xFF72D5C6), size: 18),
                SizedBox(width: 8),
                Text('Instant switch between Admin, Owner, and Advertiser',
                    style: TextStyle(
                        color: Color(0xFFD4E6E9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ]),
      );

  Widget _formPanel() => Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                  color: ink.withValues(alpha: .06),
                  blurRadius: 28,
                  offset: const Offset(0, 12))
            ]),
        child: Form(
          key: formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(createAccount ? 'Create your account' : 'Welcome back',
                style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 25,
                    letterSpacing: -.5)),
            const SizedBox(height: 6),
            Text(
                createAccount
                    ? 'Get started with SMARTADS in a few steps.'
                    : 'Sign in to continue to your SMARTADS workspace.',
                style: const TextStyle(color: Color(0xFF73828A), height: 1.4)),
            const SizedBox(height: 20),

            // Quick Access Section
            _quickAccessSection(),

            if (createAccount) ...[
              TextFormField(
                  controller: name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) => (value?.trim().length ?? 0) < 2
                      ? 'Enter your name.'
                      : null),
              const SizedBox(height: 14),
            ],
            TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) {
                  if (selectedQuickRole != null) {
                    setState(() => selectedQuickRole = null);
                  }
                },
                decoration: const InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.mail_outline)),
                validator: (value) => value == null || !value.contains('@')
                    ? 'Enter a valid email.'
                    : null),
            const SizedBox(height: 14),
            TextFormField(
                controller: password,
                obscureText: obscure,
                onChanged: (_) {
                  if (selectedQuickRole != null) {
                    setState(() => selectedQuickRole = null);
                  }
                },
                decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined))),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters.'
                    : null),
            if (createAccount) ...[
              const SizedBox(height: 18),
              const Text('I want to join as',
                  style: TextStyle(
                      color: ink, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 9),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: 'advertiser',
                      label: Text('Advertiser'),
                      icon: Icon(Icons.campaign_outlined)),
                  ButtonSegment(
                      value: 'owner',
                      label: Text('Billboard owner'),
                      icon: Icon(Icons.business_outlined))
                ],
                selected: {role},
                onSelectionChanged: (value) =>
                    setState(() => role = value.first),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: busy ? null : submit,
              style: FilledButton.styleFrom(
                  backgroundColor: teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: busy
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(createAccount ? 'Create account' : 'Sign in',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 14),
            TextButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          createAccount = !createAccount;
                          selectedQuickRole = null;
                        });
                      },
                child: Text(
                    createAccount
                        ? 'Already have an account?  Sign in'
                        : 'New to SMARTADS?  Create an account',
                    style: const TextStyle(
                        color: teal, fontWeight: FontWeight.w700))),
            const SizedBox(height: 4),
            const Text('By continuing, you agree to use SMARTADS responsibly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9AA6A8), fontSize: 11)),
          ]),
        ),
      );

  Widget _quickAccessSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2EBE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.bolt_rounded, size: 14, color: teal),
              ),
              const SizedBox(width: 8),
              const Text(
                'QUICK DEMO ACCESS',
                style: TextStyle(
                  color: Color(0xFF426563),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.7,
                ),
              ),
              const Spacer(),
              const Text(
                'Tap to autofill',
                style: TextStyle(
                  color: Color(0xFF8A9C9B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Expanded(
                    child: _demoAccountCard(
                      label: 'Admin',
                      role: 'admin',
                      emailVal: 'admin@smartads.com',
                      passwordVal: 'admin1234',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF4F46E5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _demoAccountCard(
                      label: 'Owner',
                      role: 'owner',
                      emailVal: 'owner@smartads.com',
                      passwordVal: 'owner1234',
                      icon: Icons.business_rounded,
                      color: const Color(0xFF087E78),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _demoAccountCard(
                      label: 'Advertiser',
                      role: 'advertiser',
                      emailVal: 'advertiser@smartads.com',
                      passwordVal: 'advertiser1234',
                      icon: Icons.campaign_rounded,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _demoAccountCard({
    required String label,
    required String role,
    required String emailVal,
    required String passwordVal,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = selectedQuickRole == role;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectQuickAccount(
          accountRole: role,
          accountEmail: emailVal,
          accountPassword: passwordVal,
        ),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE2EBE7),
              width: isSelected ? 1.6 : 1.0,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              else
                BoxShadow(
                  color: ink.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? color : color.withValues(alpha: 0.8)),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: const Color(0xFF72D5C6), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
        ),
      ]);
}
