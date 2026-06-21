; Inno Setup script — builds the installable Lanway Windows setup
; (lanway-windows-setup.exe). Invoked from .github/workflows/release.yml via ISCC.
; Paths are relative to this file's folder (client/windows).

#define MyAppName "Lanway"
#define MyAppVersion "1.0.0"
#define MyAppExeName "lanway_client.exe"
#define MyAppPublisher "Lanway"
#define MyAppURL "https://lanway.org"

[Setup]
AppId={{B4E6F2A0-1C3D-4E9B-9A7C-0A1B2C3D4E5F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\Lanway
DefaultGroupName=Lanway
DisableProgramGroupPage=yes
OutputBaseFilename=lanway-windows-setup
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
Name: "{group}\Lanway"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Lanway"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Lanway"; Flags: nowait postinstall skipifsilent
