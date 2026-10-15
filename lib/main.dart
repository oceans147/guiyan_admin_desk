import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'services/api_service.dart';
import 'services/config_store.dart';
import 'services/token_store.dart';
import 'screens/login_screen.dart';
import 'screens/video_render_selftest.dart';
import 'screens/workbench_screen.dart';
import 'state/auth_controller.dart';
import 'state/workspace_controller.dart';

/// 视频渲染自检开关:--dart-define=VIDEO_SELFTEST=1 启动时直接进自检页
const _kVideoSelfTest = bool.fromEnvironment('VIDEO_SELFTEST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // media_kit(libmpv)全局初始化,幂等可重复调用
  MediaKit.ensureInitialized();

  final tokenStore = TokenStore();
  await tokenStore.init();
  final configStore = ConfigStore();
  await configStore.init();

  final api = ApiService(
    tokenStore: tokenStore,
    storeUrl: AppConstants.frpStoreUrl,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        Provider<TokenStore>.value(value: tokenStore),
        ChangeNotifierProvider(
          create: (_) => AuthController(api: api, tokenStore: tokenStore),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              WorkspaceController(configStore: configStore, api: api)..bootstrap(),
        ),
      ],
      child: const GuiyanDeviceApp(),
    ),
  );
}

class GuiyanDeviceApp extends StatelessWidget {
  const GuiyanDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轨眼设备管理系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2d2d30),
        scaffoldBackgroundColor: const Color(0xFF1e1e1e),
      ),
      home: _kVideoSelfTest ? const VideoRenderSelfTest() : const _RootGate(),
    );
  }
}

/// 启动门:有有效 token 直接进主界面,否则停在登录页。← tryAutoLogin()
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  late final Future<bool> _auto;

  @override
  void initState() {
    super.initState();
    _auto = context.read<AuthController>().tryAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _auto,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snap.data == true ? const WorkbenchScreen() : const LoginScreen();
      },
    );
  }
}
