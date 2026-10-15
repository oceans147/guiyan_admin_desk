enum AuthType { password, key }

/// 一条连接配置,对应 config-store.js 里的 connection 结构。
class SSHConnection {
  String id;
  String name;
  String host;
  int port;
  String frpDomain;
  String username;
  AuthType authType;
  String password;
  String privateKeyPath;
  String privateKey;
  String passphrase;

  SSHConnection({
    this.id = '',
    this.name = '',
    required this.host,
    this.port = 22,
    this.frpDomain = '',
    required this.username,
    this.authType = AuthType.password,
    this.password = '',
    this.privateKeyPath = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  factory SSHConnection.fromJson(Map<String, dynamic> j) => SSHConnection(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 22,
        frpDomain: j['frpDomain'] as String? ?? '',
        username: j['username'] as String? ?? '',
        authType: j['authType'] == 'key' ? AuthType.key : AuthType.password,
        password: j['password'] as String? ?? '',
        privateKeyPath: j['privateKeyPath'] as String? ?? '',
        privateKey: j['privateKey'] as String? ?? '',
        passphrase: j['passphrase'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'frpDomain': frpDomain,
        'username': username,
        'authType': authType.name,
        'password': password,
        'privateKeyPath': privateKeyPath,
        'privateKey': privateKey,
        'passphrase': passphrase,
      };

  /// 对应 renderer.js connectDevice() 的设备直连默认配置。
  factory SSHConnection.forDevice(String deviceName) => SSHConnection(
        name: deviceName,
        host: '10.8.0.1',
        port: 5002,
        frpDomain: deviceName,
        username: 'cv',
        password: 'xsxc.minipc.12.34',
        authType: AuthType.password,
      );

  String get displayTitle => name.isNotEmpty ? name : '$username@$host';
}
