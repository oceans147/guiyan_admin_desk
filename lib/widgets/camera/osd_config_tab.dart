import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import 'cam_fields.dart';

/// OSD 配置 Tab。← cameraconfig/index.vue tab name=5(getOsdConfig/setOsdConfig)
class OsdConfigTab extends StatefulWidget {
  const OsdConfigTab(
      {super.key, required this.deviceId, required this.parentDeviceId});
  final String deviceId;
  final String parentDeviceId;

  @override
  State<OsdConfigTab> createState() => _OsdConfigTabState();
}

class _OsdConfigTabState extends State<OsdConfigTab> {
  Map<String, dynamic> _form = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// 文本/数字输入框,按表单路径存放(加载完成后重建)。
  final Map<String, TextEditingController> _ctrls = {};

  static const _inputPaths = [
    'TextOverlayList.TextOverlays.0.DisplayText',
    'TextOverlayList.TextOverlays.0.PositionX',
    'TextOverlayList.TextOverlays.0.PositionY',
    'DateTimeOverlay.PositionX',
    'DateTimeOverlay.PositionY',
    'ChannelNameOverlay.PositionX',
    'ChannelNameOverlay.PositionY',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  /// 取(或创建)TextOverlays[0] 的原始 Map,保证后续修改能回写到表单。
  Map<String, dynamic> _textOverlay() {
    var tl = _form['TextOverlayList'];
    if (tl is! Map<String, dynamic>) {
      tl = <String, dynamic>{};
      _form['TextOverlayList'] = tl;
    }
    var list = tl['TextOverlays'];
    if (list is! List) {
      list = <dynamic>[];
      tl['TextOverlays'] = list;
    }
    if (list.isEmpty) {
      list.add(<String, dynamic>{
        'ID': 1,
        'Enabled': true,
        'PositionX': null,
        'PositionY': null,
        'DisplayText': '',
        'Alignment': 0,
      });
    } else if (list.first is! Map<String, dynamic>) {
      list[0] = Map<String, dynamic>.from(list.first as Map);
    }
    return list.first as Map<String, dynamic>;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getOsdConfig(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final r = decodeScene(res);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _form = r.data;
      if (_error == null) {
        // 保证 TextOverlays[0] 存在,再初始化输入框 ← getOsdInfo()
        final overlay = _textOverlay();
        for (final c in _ctrls.values) {
          c.dispose();
        }
        _ctrls.clear();
        for (final p in _inputPaths) {
          final Object? v;
          if (p.startsWith('TextOverlayList')) {
            v = overlay[p.split('.').last];
          } else {
            v = pathGet(_form, p);
          }
          _ctrls[p] = TextEditingController(text: v?.toString() ?? '');
        }
      }
    });
  }

  void _set(String path, Object? v) => setState(() => pathSet(_form, path, v));

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : null,
      duration: const Duration(seconds: 2),
    ));
  }

  /// 提交前把输入框内容回写表单。← onOverlaySubmit()
  Future<void> _submit() async {
    final overlay = _textOverlay();
    Object? val(String p) {
      final t = _ctrls[p]?.text ?? '';
      return p.endsWith('DisplayText') ? t : num.tryParse(t);
    }

    overlay['DisplayText'] = val('TextOverlayList.TextOverlays.0.DisplayText');
    overlay['PositionX'] = val('TextOverlayList.TextOverlays.0.PositionX');
    overlay['PositionY'] = val('TextOverlayList.TextOverlays.0.PositionY');
    pathSet(_form, 'DateTimeOverlay.PositionX',
        val('DateTimeOverlay.PositionX'));
    pathSet(_form, 'DateTimeOverlay.PositionY',
        val('DateTimeOverlay.PositionY'));
    pathSet(_form, 'ChannelNameOverlay.PositionX',
        val('ChannelNameOverlay.PositionX'));
    pathSet(_form, 'ChannelNameOverlay.PositionY',
        val('ChannelNameOverlay.PositionY'));

    setState(() => _busy = true);
    final res = await _api.setOsdConfig(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        body: _form);
    if (!mounted) return;
    setState(() => _busy = false);
    if (sceneSetOk(res)) {
      _toast('修改成功');
      _load();
    } else {
      _toast(decodeScene(res).error ?? '修改失败', error: true);
    }
  }

  Widget _input(String label, String path, {bool numeric = false}) =>
      CamInputField(
          label: label,
          controller: _ctrls[path]!,
          numeric: numeric,
          onChanged: () {});

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败：$_error', style: const TextStyle(color: Colors.redAccent)),
          TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试')),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 注:web 端“闪烁/透明”两个标签与字段绑定就是对调的,保持一致
            CamField(
              label: 'OSD属性-闪烁',
              child: CamBoolDropdown(
                value: pathBool(_form, 'Attribute.Transparent'),
                trueLabel: '透明',
                falseLabel: '不透明',
                onChanged: (v) => _set('Attribute.Transparent', v),
              ),
            ),
            CamField(
              label: 'OSD属性-透明',
              child: CamBoolDropdown(
                value: pathBool(_form, 'Attribute.Flashing'),
                trueLabel: '闪烁',
                falseLabel: '不闪烁',
                onChanged: (v) => _set('Attribute.Flashing', v),
              ),
            ),
            CamField(
              label: 'OSD字体',
              child: CamDropdown(
                value: pathStr(_form, 'FontSize'),
                items: camItems({
                  '16*16': '16*16',
                  '32*32': '32*32',
                  '48*48': '48*48',
                  '64*64': '64*64',
                  'adaptive': '自适应'
                }),
                onChanged: (v) => _set('FontSize', v),
              ),
            ),
            CamField(
              label: 'OSD颜色',
              child: CamDropdown(
                value: pathStr(_form, 'FrontColorMode'),
                items: camItems({'auto': '黑白自动'}),
                onChanged: (v) => _set('FrontColorMode', v),
              ),
            ),
            CamField(
              label: '对齐方式',
              child: CamDropdown(
                value: pathStr(_form, 'Alignment'),
                items: camItems({
                  'customize': '自定义',
                  'alignRight': '字符右对齐',
                  'alignLeft': '字符左对齐',
                  'allLeft': '全部左对齐',
                  'allRight': '全部右对齐',
                  'GB': '国际模式'
                }),
                onChanged: (v) => _set('Alignment', v),
              ),
            ),
            CamField(
              label: '时间格式',
              child: CamDropdown(
                value: pathStr(_form, 'DateTimeOverlay.TimeStyle'),
                items: camItems({'12hour': '12小时制', '24hour': '24小时制'}),
                onChanged: (v) => _set('DateTimeOverlay.TimeStyle', v),
              ),
            ),
            CamField(
              label: '日期格式',
              child: CamDropdown(
                value: pathStr(_form, 'DateTimeOverlay.DateStyle'),
                items: camItems({
                  'YYYY-MM-DD': 'XXXX-XX-XX(年月日)',
                  'MM-DD-YYYY': 'XX-XX-XXXX(月日年)',
                  'DD-MM-YYYY': 'XX-XX-XXXX(日月年)',
                  'CHR-YYYY-MM-DD': 'XXXX年XX月XX日',
                  'CHR-MM-DD-YYYY': 'XX月XX日XXXX年',
                  'CHR-DD-MM-YYYY': 'XX日XX月XXXX年',
                  'CHR-YYYY/MM/DD': 'XXXX/XX/XX（年月日）',
                  'CHR-MM/DD/YYYY': 'XX/XX/XXXX（月日年）',
                  'CHR-DD/MM/YYYY': 'XX/XX/XXXX（日月年）',
                }),
                onChanged: (v) => _set('DateTimeOverlay.DateStyle', v),
              ),
            ),
            _input('文字描述', 'TextOverlayList.TextOverlays.0.DisplayText'),
            _input('文字描述X位置', 'TextOverlayList.TextOverlays.0.PositionX',
                numeric: true),
            _input('文字描述Y位置', 'TextOverlayList.TextOverlays.0.PositionY',
                numeric: true),
            _input('日期文字X位置', 'DateTimeOverlay.PositionX', numeric: true),
            _input('日期文字Y位置', 'DateTimeOverlay.PositionY', numeric: true),
            _input('频道名称文字X位置', 'ChannelNameOverlay.PositionX',
                numeric: true),
            _input('频道名称字Y位置', 'ChannelNameOverlay.PositionY',
                numeric: true),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _submit,
                style:
                    FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('设置')),
          ],
        ),
      ),
    );
  }
}
