import 'package:flutter_test/flutter_test.dart';
import 'package:guiyan_admin_desk/models/ssh_connection.dart';

void main() {
  test('SSHConnection forDevice uses frp defaults', () {
    final c = SSHConnection.forDevice('dev-001');
    expect(c.host, '10.8.0.1');
    expect(c.port, 5002);
    expect(c.frpDomain, 'dev-001');
    expect(c.username, 'cv');
    expect(c.displayTitle, 'dev-001');
  });

  test('SSHConnection json round-trips', () {
    final c = SSHConnection(
      id: 'x1',
      name: 'lab',
      host: '1.2.3.4',
      port: 2222,
      username: 'root',
      authType: AuthType.key,
    );
    final back = SSHConnection.fromJson(c.toJson());
    expect(back.id, 'x1');
    expect(back.port, 2222);
    expect(back.authType, AuthType.key);
  });
}
