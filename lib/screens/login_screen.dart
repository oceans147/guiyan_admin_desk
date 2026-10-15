import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'workbench_screen.dart';

/// 登录页,← #login-screen。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pwd = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthController>().loadCaptcha();
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final ok =
        await auth.login(_user.text.trim(), _pwd.text, _code.text.trim());
    if (ok && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WorkbenchScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: const [
                      Text('⚡', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('轨眼设备管理系统',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('登录以进入设备管理与远程终端',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: '账号'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwd,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                  ),
                  if (auth.captchaEnabled) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            maxLength: 6,
                            decoration: const InputDecoration(labelText: '验证码'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: auth.loadCaptcha,
                          child: SizedBox(
                            width: 100,
                            height: 38,
                            child: auth.captchaBase64 == null
                                ? Container(color: Colors.black26)
                                : Image.memory(
                                    base64Decode(auth.captchaBase64!),
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.low,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (auth.errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        auth.errorMsg!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: auth.loading ? null : _submit,
                    child: Text(auth.loading ? '登录中…' : '登 录'),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text('Copyright © taiqiuai.cn',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
