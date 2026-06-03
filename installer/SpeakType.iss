; Inno Setup script for SpeakType — a per-user installer (no admin / UAC prompt).
; Produces installer\output\SpeakTypeSetup.exe wrapping the published single-file SpeakType.exe.
; Gives the app a Start Menu entry, an optional Desktop shortcut, and a clean uninstall
; (Add/Remove Programs). The exe is unsigned, so SmartScreen still warns on the setup — only a
; code-signing certificate removes that (separate, optional).
;
; Build (on Windows, with Inno Setup 6): ISCC.exe installer\SpeakType.iss
; CI builds it after publishing the exe; see .github/workflows/ci.yml.

#define AppName "SpeakType"
#define AppVersion "1.0.0"
#define AppPublisher "SpeakType"
#define AppExeName "SpeakType.exe"
; Path to the published single-file exe, relative to this .iss (installer\).
#define AppExeSource "..\SpeakType.App\bin\Release\net8.0-windows\win-x64\publish\SpeakType.exe"

[Setup]
; A fixed AppId so upgrades replace the previous install instead of stacking.
AppId={{A14E0322-3521-4519-B5C1-714535A433D6}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; Per-user install: no admin rights, no UAC prompt.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
SetupIconFile=..\SpeakType.App\Assets\speaktype.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir=output
OutputBaseFilename=SpeakTypeSetup

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#AppExeSource}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
