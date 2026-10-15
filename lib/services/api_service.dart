import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/constants.dart';
import 'token_store.dart';

class ApiResult {
  final bool ok;
  final bool unauthorized;
  final Object? data;
  final String? error;
  final int? httpStatus;

  const ApiResult({
    required this.ok,
    this.unauthorized = false,
    this.data,
    this.error,
    this.httpStatus,
  });

  ApiResult.fail(this.error, {this.unauthorized = false, this.httpStatus})
      : ok = false,
        data = null;
}

/// 登录 / 验证码 / 设备列表 / 鉴权请求,← main.js 中的 auth/api/device IPC。
class ApiService {
  final TokenStore tokenStore;
  final String storeUrl;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiBase,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
  ));

  ApiService({required this.tokenStore, required this.storeUrl});

  Map<String, dynamic> get _preLoginHeaders => {
        'accept': 'application/json, text/plain, */*',
        'istoken': 'false',
        'origin': AppConstants.webOrigin,
        'referer': '${AppConstants.webOrigin}/',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36',
      };

  Map<String, dynamic> get _authHeaders => {
        'accept': 'application/json, text/plain, */*',
        'authorization': 'Bearer ${tokenStore.token}',
        'origin': AppConstants.webOrigin,
        'referer': '${AppConstants.webOrigin}/',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      };

  Future<ApiResult> captcha() async {
    try {
      final resp = await _dio.get<dynamic>('/captchaImage',
          options: Options(headers: _preLoginHeaders));
      return _parse(resp);
    } on DioException catch (e) {
      return ApiResult.fail(e.message ?? '验证码请求失败');
    } catch (e) {
      return ApiResult.fail(e.toString());
    }
  }

  Future<ApiResult> login({
    required String username,
    required String password,
    required String code,
    required String uuid,
  }) async {
    try {
      final resp = await _dio.post<dynamic>(
        '/login',
        data: {'username': username, 'password': password, 'code': code, 'uuid': uuid},
        options: Options(headers: {
          ..._preLoginHeaders,
          'content-type': 'application/json;charset=UTF-8',
          'repeatsubmit': 'false',
        }),
      );
      final result = _parse(resp);
      if (result.ok && result.data is Map) {
        final d = result.data as Map;
        if (num.tryParse(d['code']?.toString() ?? '') == 200) {
          final t = d['token'] ?? (d['data'] is Map ? (d['data'])['token'] : '');
          if (t is String && t.isNotEmpty) await tokenStore.set(t);
        }
      }
      return result;
    } on DioException catch (e) {
      return ApiResult.fail(e.message ?? '登录请求失败');
    } catch (e) {
      return ApiResult.fail(e.toString());
    }
  }

  Future<ApiResult> request({
    required String path,
    String method = 'GET',
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    if (!tokenStore.hasToken) {
      return ApiResult.fail('未登录或 token 已失效，请重新登录', unauthorized: true);
    }
    try {
      final resp = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          headers: body != null
              ? {..._authHeaders, 'content-type': 'application/json;charset=UTF-8'}
              : _authHeaders,
        ),
      );
      final result = _parse(resp);
      if (result.data is Map) {
        final code = num.tryParse((result.data as Map)['code']?.toString() ?? '');
        if (resp.statusCode == 401 || code == 401) {
          await tokenStore.clear();
          final msg = (result.data as Map)['msg']?.toString() ?? '认证失败，无法访问系统资源';
          return ApiResult.fail(msg, unauthorized: true, httpStatus: resp.statusCode);
        }
      }
      return result;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        return ApiResult.fail('登录已失效', unauthorized: true, httpStatus: 401);
      }
      return ApiResult.fail(e.message ?? '接口请求失败', httpStatus: status);
    } catch (e) {
      return ApiResult.fail(e.toString());
    }
  }

  Future<ApiResult> deviceList({
    int pageNum = 1,
    int pageSize = 10,
    int deviceType = 1,
    String? deviceName,
    String? storeName,
  }) {
    return request(path: '/device/config/list', query: {
      'pageNum': pageNum,
      'pageSize': pageSize,
      'deviceType': deviceType,
      if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
      if (storeName != null && storeName.isNotEmpty) 'storeName': storeName,
    });
  }

  /// 子设备列表(不分页):球房 → 摄像头等。← /device/config/listNoPageInfo
  Future<ApiResult> subDeviceList(String parentDeviceId) {
    return request(path: '/device/config/listNoPageInfo',
        query: {'parentDeviceId': parentDeviceId});
  }

  // ===== 子设备页操作接口,← web-admin-ui api/device/* =====

  /// 重新扫描局域网摄像头。← POST /device/config/scan/{deviceId}
  Future<ApiResult> scanSubDevices(String deviceId) =>
      request(path: '/device/config/scan/$deviceId', method: 'POST');

  /// 其他摄像头扫描。← POST /device/config/scanOther/{deviceId}
  Future<ApiResult> scanOtherCameras(String deviceId) =>
      request(path: '/device/config/scanOther/$deviceId', method: 'POST');

  /// 一键设置摄像头密码(query 传参)。← POST /device/info/batchSetPass
  Future<ApiResult> batchSetPassword(
          {required String parentId, required String password}) =>
      request(path: '/device/info/batchSetPass',
          method: 'POST', query: {'parentId': parentId, 'password': password});

  /// 查询直播模式。← GET /device/live/getLiveType
  Future<ApiResult> getLiveType(String deviceId) =>
      request(path: '/device/live/getLiveType', query: {'deviceId': deviceId});

  /// 设置直播模式(query 传参)。← POST /device/live/setLiveType
  Future<ApiResult> setLiveType(String deviceId, int type) =>
      request(path: '/device/live/setLiveType',
          method: 'POST', query: {'deviceId': deviceId, 'type': type});

  // ===== 摄像头配置页(scene 系列),← web-admin-ui api/device/deviceconfig.js =====
  // 注意:这些接口外层 {code,msg,data},data 是 JSON 字符串,需二次 jsonDecode,
  // 内层结构 {"data": {...}};设置类内层 data.StatusCode == 1 表示成功。

  Map<String, dynamic> _sceneQuery(
          {required String deviceId, int channelId = 1, required String parentDeviceId}) =>
      {'deviceId': deviceId, 'channelId': channelId, 'parentDeviceId': parentDeviceId};

  /// 摄像头设备信息。← GET /device/config/scene/getCameraInfo
  Future<ApiResult> getCameraInfo(
          {required String deviceId, required String parentDeviceId}) =>
      request(path: '/device/config/scene/getCameraInfo',
          query: {'deviceId': deviceId, 'parentDeviceId': parentDeviceId});

  /// 修改摄像头设备信息。← POST /device/config/scene/setCameraInfo
  Future<ApiResult> setCameraInfo({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setCameraInfo',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 时间校正。← POST /device/config/scene/setTimeInfo
  Future<ApiResult> setTimeInfo({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setTimeInfo',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 重启设备。← POST /device/config/scene/reboot
  Future<ApiResult> rebootCamera({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/reboot',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 网络配置查询(IP 获取方式)。← GET /device/config/scene/getNetwork
  Future<ApiResult> getNetwork(
          {required String deviceId, required String parentDeviceId}) =>
      request(path: '/device/config/scene/getNetwork',
          query: {'deviceId': deviceId, 'parentDeviceId': parentDeviceId});

  /// 网络配置设置。← POST /device/config/scene/setNetwork
  Future<ApiResult> setNetwork({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setNetwork',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 图像配置查询。← GET /device/config/scene/getImageConfig
  Future<ApiResult> getImageConfig({
    required String deviceId,
    required String parentDeviceId,
  }) =>
      request(path: '/device/config/scene/getImageConfig',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId));

  /// 图像配置设置。← POST /device/config/scene/setImageConfig
  Future<ApiResult> setImageConfig({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setImageConfig',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 音频配置查询。← GET /device/config/scene/getAudioConfig
  Future<ApiResult> getAudioConfig({
    required String deviceId,
    required String parentDeviceId,
  }) =>
      request(path: '/device/config/scene/getAudioConfig',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId));

  /// 音频配置设置。← POST /device/config/scene/setAudioConfig
  Future<ApiResult> setAudioConfig({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setAudioConfig',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 视频配置查询(channelId:101 主码流 / 102 子码流)。← GET /device/config/scene/getVideoConfig
  Future<ApiResult> getVideoConfig({
    required String deviceId,
    required String parentDeviceId,
    int channelId = 101,
  }) =>
      request(
          path: '/device/config/scene/getVideoConfig',
          query: _sceneQuery(
              deviceId: deviceId,
              channelId: channelId,
              parentDeviceId: parentDeviceId));

  /// 视频配置设置。← POST /device/config/scene/setVideoConfig
  Future<ApiResult> setVideoConfig({
    required String deviceId,
    required String parentDeviceId,
    int channelId = 101,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setVideoConfig',
          method: 'POST',
          query: _sceneQuery(
              deviceId: deviceId,
              channelId: channelId,
              parentDeviceId: parentDeviceId),
          body: body);

  /// OSD 配置查询。← GET /device/config/scene/getOsdConfig
  Future<ApiResult> getOsdConfig({
    required String deviceId,
    required String parentDeviceId,
  }) =>
      request(path: '/device/config/scene/getOsdConfig',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId));

  /// OSD 配置设置。← POST /device/config/scene/setOsdConfig
  Future<ApiResult> setOsdConfig({
    required String deviceId,
    required String parentDeviceId,
    required Map<String, dynamic> body,
  }) =>
      request(
          path: '/device/config/scene/setOsdConfig',
          method: 'POST',
          query: _sceneQuery(deviceId: deviceId, parentDeviceId: parentDeviceId),
          body: body);

  /// 同步图像配置到同类型摄像头(type 传路由参数 deviceType,即 bindType)。← POST /device/config/batchSyncSetConfig
  Future<ApiResult> batchSyncSetConfig({
    required String deviceId,
    required String parentDeviceId,
    required String type,
  }) =>
      request(
          path: '/device/config/batchSyncSetConfig',
          method: 'POST',
          query: {
            'deviceId': deviceId,
            'parentDeviceId': parentDeviceId,
            'type': type,
          });

  /// 获取拉流地址(v2)。← POST /device/config/getStreamUrl/v2
  Future<ApiResult> getStreamUrlV2({
    required String deviceId,
    required String parentDeviceId,
  }) =>
      request(path: '/device/config/getStreamUrl/v2',
          method: 'POST',
          query: {'deviceId': deviceId, 'parentDeviceId': parentDeviceId,'source':'pc'});

  /// 拉流心跳(每 10s,保持会话)。← POST /device/config/stream/ping
  Future<ApiResult> streamPing({
    required String deviceId,
    required String parentDeviceId,
  }) =>
      request(path: '/device/config/stream/ping',
          method: 'POST',
          query: {'deviceId': deviceId, 'parentDeviceId': parentDeviceId});

  /// 设备详情。← GET /device/config/getDeviceById/{id}
  Future<ApiResult> deviceById(String id) =>
      request(path: '/device/config/getDeviceById/$id');

  /// 摄像头账号配置查询。← GET /device/info/getInfoByDeviceId/{deviceId}
  Future<ApiResult> cameraAccountInfo(String deviceId) =>
      request(path: '/device/info/getInfoByDeviceId/$deviceId');

  /// 新增账号配置。← POST /device/info
  Future<ApiResult> addDeviceInfo(Map<String, dynamic> body) =>
      request(path: '/device/info', method: 'POST', body: body);

  /// 修改账号配置。← PUT /device/info
  Future<ApiResult> updateDeviceInfo(Map<String, dynamic> body) =>
      request(path: '/device/info', method: 'PUT', body: body);

  /// 按 MAC 查 box app 版本。← GET /device/config/getBoxVersionByMac
  Future<ApiResult> boxVersionByMac(String deviceId, String mac) =>
      request(path: '/device/config/getBoxVersionByMac',
          query: {'deviceId': deviceId, 'mac': mac});

  /// 连接前向鉴权服务确认当前 token 是否有权访问该设备。← authorizeAccess()
  Future<({bool allow, String? reason})> authorizeAccess(String device) async {
    if (storeUrl.isEmpty) return (allow: true, reason: null);
    if (!tokenStore.hasToken) return (allow: false, reason: '未登录或 token 已失效');
    try {
      final resp = await Dio().post<dynamic>(
        '$storeUrl/access',
        data: {'token': tokenStore.token, 'device': device},
        options: Options(
          headers: {'content-type': 'application/json;charset=UTF-8'},
          responseType: ResponseType.json,
        ),
      );
      final j = resp.data;
      if (j is Map) {
        return (
          allow: j['allow'] == true,
          reason: j['reason']?.toString() ?? 'HTTP ${resp.statusCode}'
        );
      }
      return (allow: false, reason: '鉴权响应格式异常');
    } catch (e) {
      return (allow: false, reason: e.toString());
    }
  }

  ApiResult _parse(Response resp) {
    final raw = resp.data?.toString() ?? '';
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      final clip = raw.length > 120 ? raw.substring(0, 120) : raw;
      return ApiResult.fail('接口返回非 JSON: $clip', httpStatus: resp.statusCode);
    }
    return ApiResult(ok: true, data: decoded, httpStatus: resp.statusCode);
  }
}
