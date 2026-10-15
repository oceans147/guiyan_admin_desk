import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import 'cam_fields.dart';

/// 视频配置 Tab。← cameraconfig/index.vue tab name=4(getVideoConfig/setVideoConfig)
class VideoConfigTab extends StatefulWidget {
  const VideoConfigTab(
      {super.key, required this.deviceId, required this.parentDeviceId});
  final String deviceId;
  final String parentDeviceId;

  @override
  State<VideoConfigTab> createState() => _VideoConfigTabState();
}

class _VideoConfigTabState extends State<VideoConfigTab> {
  Map<String, dynamic> _form = {};
  int _channelId = 101; // 101 主码流 / 102 子码流
  String _fenbianlv = ''; // "宽*高"
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _govCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _govCtrl.dispose();
    super.dispose();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getVideoConfig(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        channelId: _channelId);
    final r = decodeScene(res);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _form = r.data;
      final w = pathStr(_form, 'Video.VideoResolutionWidth');
      final h = pathStr(_form, 'Video.VideoResolutionHeight');
      if (w.isNotEmpty && h.isNotEmpty) _fenbianlv = '$w*$h';
      _govCtrl.text = pathStr(_form, 'Video.GovLength');
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

  /// 切换码流类型 → 重新拉取对应通道配置。← changeChannel()
  Future<void> _changeChannel(int ch) async {
    if (ch == _channelId) return;
    _channelId = ch;
    await _load();
  }

  Future<void> _submit() async {
    final parts = _fenbianlv.split('*');
    if (parts.length == 2) {
      _set('Video.VideoResolutionWidth', int.tryParse(parts[0]));
      _set('Video.VideoResolutionHeight', int.tryParse(parts[1]));
    }
    final gov = int.tryParse(_govCtrl.text);
    if (gov != null) _set('Video.GovLength', gov);
    setState(() => _busy = true);
    final res = await _api.setVideoConfig(
        deviceId: widget.deviceId,
        parentDeviceId: widget.parentDeviceId,
        channelId: _channelId,
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

    final mainStream = _channelId == 101;
    final codec = pathStr(_form, 'Video.VideoCodecType');
    final qualityCtrl = pathStr(_form, 'Video.VideoQualityControlType');
    final svcOn = pathBool(_form, 'Video.SVC.Enabled') ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CamField(
              label: '码流类型',
              child: DropdownButton<int>(
                value: _channelId,
                isExpanded: true,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                dropdownColor: const Color(0xFF2d2d30),
                items: const [
                  DropdownMenuItem(value: 101, child: Text('主码流')),
                  DropdownMenuItem(value: 102, child: Text('子码流')),
                ],
                onChanged: (v) {
                  if (v != null) _changeChannel(v);
                },
              ),
            ),
            CamField(
              label: '视频类型',
              child: CamBoolDropdown(
                value: pathBool(_form, 'Audio.Enabled'),
                trueLabel: '复合流',
                falseLabel: '视频流',
                onChanged: (v) => _set('Audio.Enabled', v),
              ),
            ),
            CamField(
              label: '码率类型',
              child: CamDropdown(
                value: qualityCtrl,
                enabled: mainStream,
                items: camItems({'CBR': '定码率', 'VBR': '变码率'}),
                onChanged: (v) => _set('Video.VideoQualityControlType', v),
              ),
            ),
            CamField(
              label: '分辨率',
              child: CamDropdown(
                value: _fenbianlv,
                items: camItems(mainStream
                    ? {'1280*720': '1280*720', '1920*1080': '1920*1080'}
                    : {'640*360': '640*360', '640*480': '640*480'}),
                onChanged: (v) => setState(() => _fenbianlv = v ?? ''),
              ),
            ),
            CamField(
              label: '图像质量',
              child: CamDropdown(
                value: pathStr(_form, 'Video.FixedQuality'),
                enabled: mainStream && qualityCtrl == 'VBR',
                items: camItems({
                  '1': '最低',
                  '20': '较低',
                  '40': '低',
                  '60': '中',
                  '80': '较高',
                  '100': '高'
                }),
                onChanged: (v) => _set('Video.FixedQuality', num.tryParse(v ?? '')),
              ),
            ),
            CamField(
              label: '视频帧率(fps)',
              child: CamDropdown(
                value: pathStr(_form, 'Video.MaxFrameRate'),
                enabled: mainStream,
                items: camItems({
                  '6': '1/16',
                  '12': '1/8',
                  '25': '1/4',
                  '50': '1/2',
                  '100': '1',
                  '200': '2',
                  '400': '4',
                  '600': '6',
                  '800': '8',
                  '1000': '10',
                  '1200': '12',
                  '1500': '15',
                  '1600': '16',
                  '1800': '18',
                  '2000': '20',
                  '2200': '22',
                  '2500': '25'
                }),
                onChanged: (v) => _set('Video.MaxFrameRate', num.tryParse(v ?? '')),
              ),
            ),
            CamField(
              label: '码率上限(Kbps)',
              child: CamDropdown(
                value: pathStr(_form, 'Video.VBRUpperCap'),
                items: camItems({
                  '256': '256',
                  '512': '512',
                  '1024': '1024',
                  '2048': '2048',
                  '3072': '3072',
                  '4096': '4096',
                  '6144': '6144',
                  '8192': '8192'
                }),
                onChanged: (v) => _set('Video.VBRUpperCap', num.tryParse(v ?? '')),
              ),
            ),
            CamField(
              label: '视频编码',
              child: CamDropdown(
                value: codec,
                items: camItems({
                  'H.264': 'H.264',
                  if (!mainStream) 'MJPEG': 'MJPEG',
                  'H.265': 'H.265'
                }),
                onChanged: (v) => _set('Video.VideoCodecType', v),
              ),
            ),
            if (codec != 'MJPEG')
              CamField(
                label: '低码率模式',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'Video.LBREnabled'),
                  onChanged: (v) => _set('Video.LBREnabled', v),
                ),
              ),
            if (codec == 'H.264')
              CamField(
                label: '编码复杂度',
                child: CamDropdown(
                  value: pathStr(_form, 'Video.H264Profile'),
                  items: camItems({'Baseline': '低', 'Main': '中', 'High': '高'}),
                  onChanged: (v) => _set('Video.H264Profile', v),
                ),
              ),
            if (codec == 'H.265')
              CamField(
                label: '编码复杂度',
                child: CamDropdown(
                  value: pathStr(_form, 'Video.H265Profile'),
                  items: camItems({'Baseline': '低', 'Main': '中', 'High': '高'}),
                  onChanged: (v) => _set('Video.H265Profile', v),
                ),
              ),
            CamInputField(
                label: 'I帧复杂度',
                controller: _govCtrl,
                numeric: true,
                enabled: mainStream,
                onChanged: () {}),
            if (mainStream)
              CamField(
                label: 'SVC',
                child: CamBoolDropdown(
                  value: pathBool(_form, 'Video.SVC.Enabled'),
                  onChanged: (v) => _set('Video.SVC.Enabled', v),
                ),
              ),
            if (svcOn)
              CamField(
                label: 'SVC模式',
                child: CamDropdown(
                  value: pathStr(_form, 'Video.SVC.SVCMode'),
                  items: camItems({'auto': '自动', 'manual': '手动'}),
                  onChanged: (v) => _set('Video.SVC.SVCMode', v),
                ),
              ),
            if (codec != 'MJPEG')
              CamSliderField(
                  label: '码流平滑',
                  value: pathInt(_form, 'Video.Smoothing'),
                  onChanged: (v) => _set('Video.Smoothing', v)),
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
