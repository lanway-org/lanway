; Inno Setup script — builds the installable Lanway Manager Windows setup
; (lanway-manager-windows-setup.exe). Invoked from .github/workflows/release.yml.
; Paths are relative to this file's folder (manager/windows).

#define MyAppName "Lanway Manager"
#define MyAppVersion "1.0.0"
#define MyAppExeName "lanway_manager.exe"
#define MyAppPublisher "Lanway"
#define MyAppURL "https://lanway.org"

[Setup]
AppId={{C5F7A3B1-2D4E-4F0A-8B9C-1D2E3F4A5B6C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\Lanway Manager
DefaultGroupName=Lanway Manager
DisableProgramGroupPage=yes
OutputBaseFilename=lanway-manager-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\Lanway Manager"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Lanway Manager"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Lanway Manager"; Flags: nowait postinstall skipifsilent
