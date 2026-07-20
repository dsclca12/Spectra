; Spectra — Inno Setup Installer Script
; Build: iscc /DMyAppVersion=0.1.0 installer.iss

#define MyAppName "Spectra"
#define MyAppPublisher "Spectra Project"
#define MyAppURL "https://github.com/dsclca12/Spectra"
#define MyAppExeName "spectra.exe"
#ifndef MyAppVersion
  #define MyAppVersion "0.4.5"
#endif

[Setup]
AppId={{B8F4C3A1-7E2D-4A9F-9C6B-5D3E8F2A1C4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
VersionInfoVersion={#MyAppVersion}.0

DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes

; Output
OutputDir=.
OutputBaseFilename=Spectra-{#MyAppVersion}-Setup

; Compression
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMADictionarySize=65536

; Windows version range
MinVersion=10.0.19041
PrivilegesRequired=admin

; Icon
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; License
LicenseFile=LICENSE

; Misc
DisableProgramGroupPage=yes
DisableWelcomePage=no
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: checkedonce

[Files]
; Main executable
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Flutter runtime
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion

; ONNX Runtime (optional — only included if built; AI/ML features disabled by default)
Source: "build\windows\x64\runner\Release\onnxruntime.dll"; DestDir: "{app}"; Flags: ignoreversion external
Source: "build\windows\x64\runner\Release\onnxruntime_providers_shared.dll"; DestDir: "{app}"; Flags: ignoreversion external
Source: "build\windows\x64\runner\Release\ort_bridge.dll"; DestDir: "{app}"; Flags: ignoreversion external

; Image preprocessing (optional)
Source: "build\windows\x64\runner\Release\nchw_preprocess.dll"; DestDir: "{app}"; Flags: ignoreversion external

; SQLite
Source: "build\windows\x64\runner\Release\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\sqlite3_flutter_libs_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; Plugins
Source: "build\windows\x64\runner\Release\desktop_drop_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\screen_retriever_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\window_manager_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; App data bundle (flutter assets, shaders, etc.)
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; License
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "运行 Spectra"; Flags: postinstall nowait skipifsilent shellexec

[UninstallRun]
Filename: "{cmd}"; Parameters: "/c taskkill /f /im {#MyAppExeName} 2>nul"; Flags: runhidden
