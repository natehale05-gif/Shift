; Inno Setup script for the SHIFT AI Windows installer.
;
; Built by .github/workflows/release.yml, which passes the version:
;   iscc /DAppVersion=0.1.2 windows\installer\shift_ai.iss
;
; PrivilegesRequired=lowest is deliberate and load-bearing. It installs into
; %LOCALAPPDATA%\Programs\SHIFT AI, which the user owns, so the in-app updater
; can replace the directory and relaunch. An all-users install under Program
; Files would be root-owned, the swap would fail, and every update would have
; to be downloaded by hand. The user can still elect an all-users install from
; the privileges dialog; the app detects that it cannot write to its own
; directory and says so rather than failing mid-update.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "SHIFT AI"
#define AppExe "shift_ai.exe"
#define AppPublisher "shiftai.club"
#define AppUrl "https://github.com/natehale05-gif/Shift"

[Setup]
AppId={{6F3A2D14-8C5B-4E27-9A61-0D7C8B4F52E9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename=SHIFT-AI-windows-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; The builds are unsigned, so SmartScreen warns once. Saying so here is more
; use than leaving people to guess at the blue box.
AppComments=Unsigned build. SmartScreen will warn on first run: More info -> Run anyway.

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The updater unpacks the next version beside the install before swapping it
; in. If someone uninstalls while one is staged, that directory is not owned
; by the installer's file list and would otherwise be left behind.
Type: filesandordirs; Name: "{app}_staged"
Type: filesandordirs; Name: "{app}_backup"
Type: filesandordirs; Name: "{app}_incoming"
