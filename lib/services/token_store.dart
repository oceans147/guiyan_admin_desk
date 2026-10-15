import 'package:shared_preferences/shared_preferences.dart';

/// token 与界面偏好持久化,← renderer.js 的 localStorage('frp-shell-token')
/// 及 main.js 的 currentToken。
class TokenStore {
  static const _tokenKey = 'frp-shell-token';
  static const _connKey = 'panel-conn';
  static const _fileKey = 'panel-file';

  SharedPreferences? _prefs;
  String _token = '';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs?.getString(_tokenKey) ?? '';
  }

  String get token => _token;
  bool get hasToken => _token.isNotEmpty;

  Future<void> set(String t) async {
    _token = t;
    await _prefs?.setString(_tokenKey, t);
  }

  Future<void> clear() async {
    _token = '';
    await _prefs?.remove(_tokenKey);
  }

  Future<void> savePanelWidths(int conn, int file) async {
    await _prefs?.setInt(_connKey, conn);
    await _prefs?.setInt(_fileKey, file);
  }

  (int, int) getPanelWidths() => (
        _prefs?.getInt(_connKey) ?? 240,
        _prefs?.getInt(_fileKey) ?? 400,
      );
}
