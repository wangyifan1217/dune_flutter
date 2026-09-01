; 与 dist/windows/dunes-setup.iss 保持同一 AppId / 权限，否则升级找不到旧目录。
#define MyAppName "沙丘"
#define MyAppVersion "1.5.6"
#define MyAppBuild "156"
#define MyAppPublisher "沙丘"
#define MyAppExeName "dunes_app.exe"

[Setup]
; 历史安装（含 1.2.1-110）使用此 AppId；勿改，否则 UsePreviousAppDir 失效。
AppId={{A8E2C1D4-7B5F-4E9A-9C3D-1F2A6B8E0D71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion} ({#MyAppBuild})
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\DunesDesktop
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UsePreviousAppDir=yes
OutputDir=..\..\build\installer
OutputBaseFilename=DunesSetup-{#MyAppVersion}-{#MyAppBuild}
VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 与历史包一致：默认当前用户安装，才能读到 HKCU 里旧目录（如 D:\DunesDesktop）。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Flutter 引擎依赖 GetHostNameW（Win8+），且官方仅支持 Windows 10+。
MinVersion=10.0
; 更新时静默强制关闭占用文件的 dunes_app，不再弹出 Files in Use 确认页。
CloseApplications=force
RestartApplications=no

[Messages]
WindowsVersionNotSupported=沙丘 PC 端需要 64 位 Windows 10 或更高版本。%n%n当前系统过旧（如 Windows 7），无法运行。请升级系统或换一台 Win10/Win11 电脑安装。

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
