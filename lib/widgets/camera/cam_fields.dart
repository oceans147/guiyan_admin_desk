import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';

/// 错误信息里附带原始响应摘要,便于直接定位后端返回内容
String _preview(Object? v) {
  final s = v?.toString() ?? 'null';
  return s.length <= 120 ? s : '${s.substring(0, 120)}…';
}

/// scene 系列接口响应:外层 {code,msg,data},data 是 JSON 字符串,
/// 需二次 jsonDecode,内层 {"data": {...}}。← web 端 JSON.parse(res.data)
({int code, Map<String, dynamic> data, int statusCode, String? error})
    decodeScene(ApiResult res) {
  final outer = res.data;
  if (outer is! Map) {
    return (code: -1, data: {}, statusCode: -1, error: res.error ?? '响应格式错误');
  }
  final outerCode =
      num.tryParse(outer['code']?.toString() ?? '')?.toInt() ?? -1;
  if (outerCode != 200) {
    return (
      code: outerCode,
      data: {},
      statusCode: -1,
      error: outer['msg']?.toString() ?? '请求失败'
    );
  }
  // data 为 JSON 字符串(dio plain 模式)
  Object? inner = outer['data'];
  // 设备离线/通道异常时,后端会返回 {code:200, data:null} 或空串
  if (inner == null || (inner is String && inner.trim().isEmpty)) {
    return (
        code: 200,
        data: {},
        statusCode: -1,
        error: '设备未返回配置数据，可能离线，请确认设备在线后重试');
  }
  // 部分情况下会被双重 JSON 编码,循环解到非字符串为止(最多 2 次)
  for (var i = 0; i < 2 && inner is String; i++) {
    try {
      inner = jsonDecode(inner);
    } catch (_) {
      return (
          code: 200,
          data: {},
          statusCode: -1,
          error: '内层 JSON 解析失败：${_preview(outer['data'])}');
    }
  }
  if (inner is! Map) {
    return (
        code: 200,
        data: {},
        statusCode: -1,
        error: '内层数据格式错误：${_preview(outer['data'])}');
  }
  final payload = inner['data'];
  return (
    code: 200,
    data: payload is Map
        ? payload.cast<String, dynamic>()
        : <String, dynamic>{},
    statusCode: payload is Map
        ? num.tryParse(payload['StatusCode']?.toString() ?? '')?.toInt() ?? -1
        : -1,
    error: null,
  );
}

/// 设置类接口是否成功:内层 data.StatusCode == 1。
bool sceneSetOk(ApiResult res) {
  final r = decodeScene(res);
  return r.code == 200 && r.statusCode == 1;
}

/// 按 "A.B.C" 路径读取嵌套 Map 值。
Object? pathGet(Map<String, dynamic> map, String path) {
  Object? cur = map;
  for (final seg in path.split('.')) {
    if (cur is Map) {
      cur = cur[seg];
    } else {
      return null;
    }
  }
  return cur;
}

/// 按 "A.B.C" 路径写入嵌套 Map,中间层缺失时自动创建。
void pathSet(Map<String, dynamic> map, String path, Object? value) {
  final segs = path.split('.');
  Map<String, dynamic> cur = map;
  for (final seg in segs.take(segs.length - 1)) {
    final next = cur[seg];
    if (next is Map<String, dynamic>) {
      cur = next;
    } else {
      final created = <String, dynamic>{};
      cur[seg] = created;
      cur = created;
    }
  }
  cur[segs.last] = value;
}

int? pathInt(Map<String, dynamic> map, String path) =>
    num.tryParse(pathGet(map, path)?.toString() ?? '')?.toInt();

bool? pathBool(Map<String, dynamic> map, String path) {
  final v = pathGet(map, path);
  if (v == null) return null;
  if (v is bool) return v;
  return v.toString().toLowerCase() == 'true';
}

String pathStr(Map<String, dynamic> map, String path, {String def = ''}) =>
    pathGet(map, path)?.toString() ?? def;

/// 表单行:左侧固定宽标签 + 右侧控件。
class CamField extends StatelessWidget {
  const CamField(
      {super.key, required this.label, required this.child, this.labelWidth = 130});
  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 字符串值下拉框。
class CamDropdown extends StatelessWidget {
  const CamDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.hint = '请选择',
  });

  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String hint;

  @override
  Widget build(BuildContext context) {
    // 当前值不在选项中时以占位显示,避免 DropdownButton 断言失败
    final valid = items.any((e) => e.value == value);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: valid ? value : null,
        isExpanded: true,
        disabledHint: Text(value ?? '-',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        style: const TextStyle(fontSize: 12, color: Colors.white),
        dropdownColor: const Color(0xFF2d2d30),
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// 布尔值下拉框(true/false)。
class CamBoolDropdown extends StatelessWidget {
  const CamBoolDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.trueLabel = '开启',
    this.falseLabel = '关闭',
  });

  final bool? value;
  final ValueChanged<bool> onChanged;
  final String trueLabel;
  final String falseLabel;

  @override
  Widget build(BuildContext context) {
    return CamDropdown(
      value: value?.toString(),
      items: [
        DropdownMenuItem(value: 'true', child: Text(trueLabel)),
        DropdownMenuItem(value: 'false', child: Text(falseLabel)),
      ],
      onChanged: (v) => onChanged(v == 'true'),
    );
  }
}

/// 整数滑块(带数值显示)。
class CamSliderField extends StatelessWidget {
  const CamSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? min).clamp(min, max).toDouble();
    return CamField(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: v,
              min: min.toDouble(),
              max: max.toDouble(),
              activeColor: Colors.lightBlue,
              onChanged: (x) => onChanged(x.round()),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(v.round().toString(),
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// 文本/数字输入行。
class CamInputField extends StatelessWidget {
  const CamInputField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.numeric = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool numeric;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return CamField(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(fontSize: 12),
        inputFormatters:
            numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        keyboardType: numeric ? TextInputType.number : null,
        decoration: const InputDecoration(
            isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        onChanged: (_) => onChanged?.call(),
      ),
    );
  }
}

/// 折叠分组(仿 web el-collapse,默认收起,展开显示子表单)。
class CamCollapse extends StatefulWidget {
  const CamCollapse({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  State<CamCollapse> createState() => _CamCollapseState();
}

class _CamCollapseState extends State<CamCollapse> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF3c3c3c)))),
            child: Row(
              children: [
                Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(fontSize: 13))),
                Icon(_open ? Icons.expand_less : Icons.chevron_right,
                    size: 18, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Column(children: widget.children),
          ),
      ],
    );
  }
}

/// 构造字符串下拉菜单项。
List<DropdownMenuItem<String>> camItems(Map<String, String> labelByValue) => [
      for (final e in labelByValue.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ];
