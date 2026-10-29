; 与 dist/windows/dunes-setup.iss 保持同一 AppId / 权限，否则升级找不到旧目录。
#define MyAppName "沙丘"
#define MyAppVersion "1.9.5"
#define MyAppBuild "195"
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
; 不能用 MinVersion=10.0。兼容模式会让安装器把 Windows 11 谎报成 Windows 7，
; 从而直接弹出「系统过旧」。真正的系统版本在下面的 [Code] 里读注册表判断。
MinVersion=6.1
; 不用 Restart Manager 的占用确认页。程序已经退出后，它仍会把 dunes_app.exe
; 列出来并停在 Preparing to Install。残留进程在 PrepareToInstall 里结束。
CloseApplications=no
RestartApplications=no
; 与 windows/runner/main.cpp 的单实例互斥量同名。进程没退出前不要开始覆盖文件。
AppMutex=Local\DunesDesktop.B5A14F5D-32E5-484D-BCB1-0156D5F7F5E5

[Messages]
WindowsVersionNotSupported=沙丘 PC 端需要 64 位 Windows 10 或更高版本。%n%n当前系统版本过低，无法安装。请升级到 Windows 10 或 Windows 11。

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

[Code]
function IsRealWindows10OrNewer: Boolean;
var
  Root: Integer;
  Major: Cardinal;
  VersionText, BuildText: String;
begin
  if IsWin64 then
    Root := HKLM64
  else
    Root := HKLM;
  Major := 0;
  VersionText := '';
  BuildText := '';
  if RegQueryDWordValue(Root, 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentMajorVersionNumber', Major) then
    Log(Format('Registry CurrentMajorVersionNumber: %d', [Major]));
  if RegQueryStringValue(Root, 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentVersion', VersionText) then
    Log('Registry CurrentVersion: ' + VersionText);
  if RegQueryStringValue(Root, 'SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentBuild', BuildText) then
    Log('Registry CurrentBuild: ' + BuildText);
  { Windows 10/11 的主版本号是 10。兼容模式改不了这个注册表值。 }
  Result := (Major >= 10) or (Copy(VersionText, 1, 3) = '10.');
end;

function InitializeSetup: Boolean;
begin
  Result := IsRealWindows10OrNewer;
  if not Result then
    MsgBox('沙丘 PC 端需要 64 位 Windows 10 或更高版本。' + #13#10 + #13#10 +
      '当前系统版本过低，无法安装。请升级到 Windows 10 或 Windows 11。',
      mbError, MB_OK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  NeedsRestart := False;
  { 不用 /T：更新时安装器可能是 dunes_app 拉起来的，/T 会把安装器一起杀掉。 }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM dunes_app.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(800);
end;
