import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// frp tcpmux 隧道,← main.js 的 frpTcpmuxTunnel()。
///
/// 向 frps(或代理)的 tcpmux 端口发送 HTTP/1.1 CONNECT `serverName`,
/// 建立隧道后把 socket 适配成 dartssh2 的 [SSHSocket] 交给 SSH 客户端。
/// 关键:握手时可能顺带读到隧道内的首批 SSH 字节,需要把它们(去掉响应头后)
/// 重新喂回给下游,避免丢包。
class FrpTunnelSocket implements SSHSocket {
  final Socket _socket;
  final StreamController<Uint8List> _in;

  FrpTunnelSocket._(this._socket, this._in);

  @override
  Stream<Uint8List> get stream => _in.stream;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> flush() => _socket.flush();

  @override
  void destroy() {
    _socket.destroy();
    if (!_in.isClosed) _in.close();
  }

  static final List<int> _headerEnd = [13, 10, 13, 10]; // \r\n\r\n

  static Future<SSHSocket> connect({
    required String host,
    required int port,
    required String serverName,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}

    final inCtl = StreamController<Uint8List>();
    final acc = BytesBuilder(copy: true);
    final done = Completer<void>();
    bool handshakeDone = false;

    socket.listen(
      (chunk) {
        if (handshakeDone) {
          inCtl.add(chunk);
          return;
        }
        acc.add(chunk);
        final bytes = acc.toBytes();
        final idx = _indexOf(bytes, _headerEnd);
        if (idx < 0) {
          if (bytes.length > 65536 && !done.isCompleted) {
            done.completeError(StateError('CONNECT 响应异常（无结束标记）'));
            socket.destroy();
          }
          return;
        }
        final head = String.fromCharCodes(bytes.sublist(0, idx));
        final statusLine = head.split('\r\n').first;
        if (!RegExp(r' 200(\s|$)').hasMatch(statusLine)) {
          if (!done.isCompleted) {
            done.completeError(StateError('frp CONNECT 被拒: $statusLine'));
          }
          socket.destroy();
          return;
        }
        handshakeDone = true;
        if (!done.isCompleted) done.complete();
        final rest = bytes.sublist(idx + 4);
        if (rest.isNotEmpty) inCtl.add(Uint8List.fromList(rest));
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(e);
        } else if (!inCtl.isClosed) {
          inCtl.addError(e);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.completeError(StateError('隧道在 CONNECT 完成前已关闭'));
        }
        if (!inCtl.isClosed) inCtl.close();
      },
      cancelOnError: false,
    );

    socket.add(_ascii('CONNECT $serverName HTTP/1.1\r\n'
        'Host: $serverName\r\n\r\n'));

    try {
      await done.future.timeout(timeout, onTimeout: () {
        throw StateError('frp CONNECT 超时');
      });
    } catch (e) {
      socket.destroy();
      rethrow;
    }

    return FrpTunnelSocket._(socket, inCtl);
  }
}

List<int> _ascii(String s) => Uint8List.fromList(s.codeUnits);

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
