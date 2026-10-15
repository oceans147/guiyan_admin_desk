/// 全局常量,对应 frp-shell 的 main.js / renderer.js 顶部配置。
class AppConstants {
  AppConstants._();

  static const apiBase = 'https://api.taiqiuai.cn/ai_admin';
  static const webOrigin = 'https://ai-admin.taiqiuai.cn';

  /// 访问端鉴权服务地址(留空则跳过鉴权)。对应环境变量 FRP_STORE_URL。
  static const frpStoreUrl =
      String.fromEnvironment('FRP_STORE_URL', defaultValue: '');

  /// 设备直连默认参数(对应 renderer.js 顶部 SSH_* 常量)。
  static const sshHost = '10.8.0.1';
  static const sshProxyPort = 5002;
  static const sshDefaultUser = 'cv';
  static const sshDefaultPassword = 'xsxc.minipc.12.34';
}
