#define MyAppName "沙丘"
#define MyAppVersion "1.2.1"
#define MyAppPublisher "Dunes"
#define MyAppExeName "dunes_app.exe"

[Setup]
AppId={{B5A14F5D-32E5-484D-BCB1-0156D5F7F5E5}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Dunes
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=DunesSetup-1.2.1-110
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Flutter 引擎依赖 GetHostNameW（Win8+），且官方仅支持 Windows 10+。
; 安装阶段拦截 Win7/Win8，避免装完启动才报 WS2_32.dll 入口点错误。
MinVersion=10.0
; 更新时静默强制关闭占用文件的 dunes_app，不再弹出 Files in Use 确认页。
; 安装完成后由下方 [Run] 拉起新版本，避免 RestartApplications 与 postinstall 双开。
CloseApplications=force
RestartApplications=no

[Messages]
WindowsVersionNotSupported=沙丘 PC 端需要 64 位 Windows 10 或更高版本。%n%n当前系统过旧（如 Windows 7），无法运行。请升级系统或换一台 Win10/Win11 电脑安装。

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
