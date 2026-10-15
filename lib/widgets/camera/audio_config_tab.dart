import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import 'cam_fields.dart';

/// 音频配置 Tab。← cameraconfig/index.vue tab name=3(getAudioConfig/setAudioConfig)
class AudioConfigTab extends StatefulWidget {
  const AudioConfigTab(
      {super.key, required this.deviceId, required this.parentDeviceId});
  final String deviceId;
  final String parentDeviceId;

  @override
  State<AudioConfigTab> createState() => _AudioConfigTabState();
}

class _AudioConfigTabState extends State<AudioConfigTab> {
  Map<String, dynamic> _form = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ApiService get _api => context.read<ApiService>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getAudioConfig(
        deviceId: widget.deviceId, parentDeviceId: widget.parentDeviceId);
    final r = decodeScene(res);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.error;
      _form = r.data;
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

  Future<void> _submit() async {
    setState(() => _busy = true);
    final res = await _api.setAudioConfig(
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

    final codec = pathStr(_form, 'AudioCompressionType');
    final showSampleRate = ['MP2L2', 'AAC', 'PCM'].contains(codec);
    final showBitRate = ['MP2L2', 'AAC'].contains(codec);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CamField(
              label: '音频编码',
              child: CamDropdown(
                value: codec,
                items: camItems({'G.711alaw': 'G.711alaw', 'AAC': 'AAC'}),
                onChanged: (v) => _set('AudioCompressionType', v),
              ),
            ),
            if (showSampleRate)
              CamField(
                label: '采样率',
                child: CamDropdown(
                  value: pathStr(_form, 'AudioSamplingRate'),
                  items: camItems({'16': '16kHz'}),
                  onChanged: (v) => _set('AudioSamplingRate', v),
                ),
              ),
            if (showBitRate)
              CamField(
                label: '音频码率',
                child: CamDropdown(
                  value: pathStr(_form, 'AudioBitRate'),
                  items: camItems({
                    for (final k in ['32', '40', '48', '56', '64', '80', '96', '112', '128', '144', '160'])
                      k: '$k kbps'
                  }),
                  onChanged: (v) => _set('AudioBitRate', v),
                ),
              ),
            CamField(
              label: '音频输入',
              child: CamDropdown(
                value: pathStr(_form, 'AudioInputType'),
                items: camItems({'MicIn': 'MicIn'}),
                onChanged: (v) => _set('AudioInputType', v),
              ),
            ),
            CamSliderField(
                label: '输入音量',
                value: pathInt(_form, 'SpeakerVolume'),
                onChanged: (v) => _set('SpeakerVolume', v)),
            CamField(
              label: '环境噪声过滤',
              child: CamBoolDropdown(
                value: pathBool(_form, 'NoiseReduce'),
                onChanged: (v) => _set('NoiseReduce', v),
              ),
            ),
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
