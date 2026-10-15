import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/ssh_connection.dart';
import '../state/workspace_controller.dart';

/// 新建/编辑连接配置弹窗。← openModal() / saveConn() / toggleAuth()
Future<void> showConnectionEditor(
    BuildContext context, WorkspaceController ws, SSHConnection? existing) {
  return showDialog(
    context: context,
    builder: (_) => _ConnectionEditorDialog(ws: ws, existing: existing),
  );
}

/// 连接管理弹窗:列表 + 连接 / 编辑 / 删除。
Future<void> showConnectionManager(
    BuildContext context, WorkspaceController ws) {
  return showDialog(
    context: context,
    builder: (_) => _ConnectionManagerDialog(ws: ws),
  );
}

class _ConnectionEditorDialog extends StatefulWidget {
  const _ConnectionEditorDialog({required this.ws, this.existing});
  final WorkspaceController ws;
  final SSHConnection? existing;

  @override
  State<_ConnectionEditorDialog> createState() => _ConnectionEditorDialogState();
}

class _ConnectionEditorDialogState extends State<_ConnectionEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _frpDomain;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _keyPath;
  late final TextEditingController _keyContent;
  late final TextEditingController _passphrase;

  late AuthType _authType;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _authType = e?.authType ?? AuthType.password;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? AppConstants.sshHost);
    _port = TextEditingController(
        text: (e?.port ?? AppConstants.sshProxyPort).toString());
    _frpDomain = TextEditingController(text: e?.frpDomain ?? '');
    _username = TextEditingController(text: e?.username ?? 'cv');
    _password = TextEditingController(text: e?.password ?? '');
    _keyPath = TextEditingController(text: e?.privateKeyPath ?? '');
    _keyContent = TextEditingController(text: e?.privateKey ?? '');
    _passphrase = TextEditingController(text: e?.passphrase ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _frpDomain.dispose();
    _username.dispose();
    _password.dispose();
    _keyPath.dispose();
    _keyContent.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _pickKeyFile() async {
    final f = await FilePicker.pickFile(dialogTitle: '选择私钥文件');
    final path = f?.path;
    if (path == null) return;
    _keyPath.text = path;
    try {
      _keyContent.text = await File(path).readAsString();
    } catch (_) {
      // 无法读取内容时保留路径,由用户手动粘贴。
    }
  }

  Future<void> _save() async {
    final host = _host.text.trim();
    final username = _username.text.trim();
    if (host.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('主机与用户名不能为空')),
      );
      return;
    }
    final conn = SSHConnection(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 22,
      frpDomain: _frpDomain.text.trim(),
      username: username,
      authType: _authType,
      password: _password.text,
      privateKeyPath: _keyPath.text.trim(),
      privateKey: _keyContent.text,
      passphrase: _passphrase.text,
    );
    await widget.ws.saveConnection(conn);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新建连接' : '编辑连接'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, '名称（可选）'),
              _field(_host, '主机 / SSH 地址'),
              _field(_port, '端口'),
              _field(_frpDomain, 'frp 域名（tcpmux 代理名，可空）'),
              _field(_username, '用户名'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<AuthType>(
                  segments: const [
                    ButtonSegment(value: AuthType.password, label: Text('密码')),
                    ButtonSegment(value: AuthType.key, label: Text('私钥')),
                  ],
                  selected: {_authType},
                  onSelectionChanged: (s) => setState(() => _authType = s.first),
                ),
              ),
              const SizedBox(height: 8),
              if (_authType == AuthType.password)
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(child: _field(_keyPath, '私钥路径')),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 18),
                      onPressed: _pickKeyFile,
                    ),
                  ],
                ),
                _area(_keyContent, '私钥内容（PEM）'),
                _field(_passphrase, '私钥口令（可空）'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(controller: c, decoration: InputDecoration(labelText: label)),
      );

  Widget _area(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextField(
          controller: c,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _ConnectionManagerDialog extends StatelessWidget {
  const _ConnectionManagerDialog({required this.ws});
  final WorkspaceController ws;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('连接管理'),
      content: SizedBox(
        width: 480,
        height: 380,
        child: ListBuilder(
          controller: ws,
          builder: (context) {
            final list = ws.connections;
            if (list.isEmpty) {
              return const Center(
                  child: Text('暂无保存的连接',
                      style: TextStyle(color: Colors.grey)));
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  dense: true,
                  title: Text(c.displayTitle),
                  subtitle: Text(
                      '${c.username}@${c.host}:${c.port}${c.frpDomain.isNotEmpty ? ' · frp:${c.frpDomain}' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '连接',
                        icon: const Icon(Icons.play_arrow, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          ws.openSession(c);
                        },
                      ),
                      IconButton(
                        tooltip: '编辑',
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          showConnectionEditor(context, ws, c);
                        },
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: const Icon(Icons.delete, size: 18),
                        onPressed: () => ws.deleteConnection(c.id),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.pop(context);
              showConnectionEditor(context, ws, null);
            },
            child: const Text('新建连接')),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}

/// 监听 [WorkspaceController] 变化重建子树。
class ListBuilder extends StatelessWidget {
  const ListBuilder({super.key, required this.controller, required this.builder});
  final WorkspaceController controller;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Builder(builder: builder),
    );
  }
}
