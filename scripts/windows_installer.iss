#define MyAppName "EZVenera"
#define MyAppPublisher "WEP-56"

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#ifndef MySourceDir
  #error "MySourceDir must be provided."
#endif

#ifndef MyOutputDir
  #error "MyOutputDir must be provided."
#endif

#ifndef MyOutputBaseFilename
  #define MyOutputBaseFilename "EZVenera-setup"
#endif

#ifndef MySetupIconFile
  #define MySetupIconFile AddBackslash(SourcePath) + "..\\windows\\runner\\resources\\app_icon.ico"
#endif

[Setup]
AppId={{84A14B44-A6B9-4B6B-8EA8-10C5410EAC18}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\EZVenera
DefaultGroupName=EZVenera
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile={#MySetupIconFile}
UninstallDisplayIcon={app}\ezvenera.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\EZVenera"; Filename: "{app}\ezvenera.exe"
Name: "{autodesktop}\EZVenera"; Filename: "{app}\ezvenera.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ezvenera.exe"; Description: "{cm:LaunchProgram,EZVenera}"; Flags: nowait postinstall skipifsilent
