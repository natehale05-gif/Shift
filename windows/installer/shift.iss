; Inno Setup script for the SHIFT AI Windows installer.
;
; Built by .github/workflows/release.yml, which passes the version:
;   iscc /DAppVersion=0.2.0 windows\installer\shift.iss
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
#define AppExe "shift.exe"
#define AppPublisher "shiftai.club"
#define AppUrl "https://github.com/natehale05-gif/Shift"

[Setup]
; A **new** GUID, not the one the deleted app used. Reusing it would make
; Windows treat this as an upgrade of that app — inheriting its uninstall entry
; and offering to replace an install of a program that no longer exists.
AppId={{E701983C-004B-44AB-8EDD-456BB02CA8A1}
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

[InstallDelete]
; Reinstalling over a copy that has a half-applied update staged beside it
; would leave that directory in place, and the freshly installed app would
; immediately try to swap it in — quit, flash a console, and come back
; unchanged, on every launch. Installing is the moment to clear it.
Type: filesandordirs; Name: "{app}_staged"
Type: filesandordirs; Name: "{app}_backup"
Type: filesandordirs; Name: "{app}_incoming"
Type: files; Name: "{app}_staged.attempted"

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
Type: files; Name: "{app}_staged.attempted"
