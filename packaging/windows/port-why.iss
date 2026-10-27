; The Windows installer for Port Why, built with Inno Setup 6 by
; package.ps1, which passes:
;
;   AppVersion  the version the app was built as (1.2.0, 1.2.0-dev.abc1234)
;   FileVersion AppVersion without a pre-release suffix (1.2.0)
;   StageDir    the folder `flutter build windows` made (port_why.exe, its
;               DLLs and data\)
;   OutputBase  the installer's file name without .exe
;   Arch        x64compatible or arm64
;
; It installs per user without asking for admin rights (an admin can pick
; all users in the first dialog), adds a Start menu entry, offers a desktop
; shortcut, and uninstalls from Settings > Apps. Favorites in
; %APPDATA%\Port Why stay behind for a reinstall.

#ifndef AppVersion
  #error AppVersion is required
#endif

[Setup]
; Never change AppId: it's how an upgrade finds the installed copy.
AppId={{5E3D9A41-7C2B-4F86-9B0E-2A6D4C1F8E73}
AppName=Port Why
AppVersion={#AppVersion}
AppVerName=Port Why {#AppVersion}
AppPublisher=ThirtyTech
AppPublisherURL=https://github.com/jsheely/port-why
AppSupportURL=https://github.com/jsheely/port-why/issues
AppUpdatesURL=https://github.com/jsheely/port-why/releases
VersionInfoVersion={#FileVersion}
DefaultDirName={autopf}\Port Why
DefaultGroupName=Port Why
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed={#Arch}
ArchitecturesInstallIn64BitMode={#Arch}
OutputDir=.
OutputBaseFilename={#OutputBase}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\port_why.exe
UninstallDisplayName=Port Why
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; The modern wizard's images at 100% and 200%; Setup picks the pair that
; suits the screen. sidebar*.bmp are sidebar.svg (24-bit), small*.bmp the
; app icon (32-bit, straight alpha); ../render.ps1 renders them all again
; after either changes.
WizardImageAlphaFormat=defined
WizardImageFile=sidebar.bmp,sidebar-2x.bmp
WizardSmallImageFile=small.bmp,small-2x.bmp
; A running Port Why holds its DLLs open; Setup closes it first (it rescans
; from scratch when it starts again).
CloseApplications=yes

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

; Flutter's assets are rebuilt whole each release, so an upgrade clears out
; the old ones rather than leaving files no release has any more.
[InstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Port Why"; Filename: "{app}\port_why.exe"
Name: "{autodesktop}\Port Why"; Filename: "{app}\port_why.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\port_why.exe"; Description: "{cm:LaunchProgram,Port Why}"; Flags: nowait postinstall skipifsilent
