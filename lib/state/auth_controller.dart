import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/token_store.dart';

/// 登录 / 验证码 / 自动登录 / 失效重登,← renderer.js 的登录相关逻辑。
class AuthController extends ChangeNotifier {
  final ApiService api;
  final TokenStore tokenStore;

  String captchaUuid = '';
  bool captchaEnabled = true;
  String? captchaBase64;
  String? errorMsg;
  bool loading = false;

  AuthController({required this.api, required this.tokenStore});

  Future<void> loadCaptcha() async {
    errorMsg = null;
    final res = await api.captcha();
    if (!res.ok) {
      errorMsg = '验证码获取失败：${res.error}';
      notifyListeners();
      return;
    }
    final d = (res.data is Map) ? res.data as Map : const {};
    captchaUuid = d['uuid']?.toString() ?? '';
    captchaEnabled = d['captchaEnabled'] != false;
    captchaBase64 = d['img'] as String?;
    notifyListeners();
  }

  Future<bool> login(String username, String password, String code) async {
    errorMsg = null;
    if (username.isEmpty || password.isEmpty) {
      errorMsg = '请输入账号和密码';
      notifyListeners();
      return false;
    }
    if (captchaEnabled && code.isEmpty) {
      errorMsg = '请输入验证码';
      notifyListeners();
      return false;
    }
    loading = true;
    notifyListeners();

    final res = await api.login(
        username: username, password: password, code: code, uuid: captchaUuid);
    loading = false;

    final d = (res.data is Map) ? res.data as Map : const {};
    final token = (d['token'] ??
            (d['data'] is Map ? (d['data'])['token'] : ''))
        ?.toString() ??
        '';
    final codeNum = num.tryParse(d['code']?.toString() ?? '');
    if (res.ok && codeNum == 200 && token.isNotEmpty) {
      await tokenStore.set(token);
      notifyListeners();
      return true;
    }
    errorMsg = '登录失败：${d['msg'] ?? res.error ?? '未知错误'}';
    notifyListeners();
    await loadCaptcha();
    return false;
  }

  /// 若本地已有 token,做一次轻量鉴权校验有效性。← tryAutoLogin()
  Future<bool> tryAutoLogin() async {
    if (!tokenStore.hasToken) return false;
    final res = await api.deviceList(pageNum: 1, pageSize: 1);
    if (res.unauthorized) {
      await tokenStore.clear();
      errorMsg = '登录已过期，请重新登录';
      notifyListeners();
      return false;
    }
    if (!res.ok) {
      errorMsg = '无法访问设备接口：${res.error}';
      notifyListeners();
      return false;
    }
    return true;
  }

  void requireRelogin(String reason) {
    errorMsg = reason;
    notifyListeners();
  }
}
