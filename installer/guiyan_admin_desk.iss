; 轨眼设备管理系统 Windows 安装包脚本(Inno Setup 6)
; 用法:在 Windows 上先执行 flutter build windows --release,
; 再用 Inno Setup 打开本文件编译,产物在 installer\Output\guiyan_admin_desk-setup.exe

#define MyAppName "轨眼设备管理系统"
#define MyAppVersion "1.0.0"
#define MyAppExeName "guiyan_admin_desk.exe"

[Setup]
AppId={{8F3E2C71-9D4B-4E8A-B6F0-GUIYANDESK01}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=轨眼
DefaultDirName={autopf}\guiyan_admin_desk
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=guiyan_admin_desk-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
UninstallDisplayName={#MyAppName}

[Languages]
; CI(GitHub Windows runner)上 Inno Setup 默认不装中文语言包:
; 定义了 CHINESE(ISCC /DCHINESE)时用中文,否则回退到内置英文,保证总能编译成功
#ifdef CHINESE
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#else
Name: "default"; MessagesFile: "compiler:Default.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Files]
; Flutter 构建产物整个目录打包(含 flutter_windows.dll、media_kit/libmpv、插件 DLL)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
