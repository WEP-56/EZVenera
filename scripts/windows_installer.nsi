Unicode true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!define MyAppName "EZVenera"
!define MyAppPublisher "WEP-56"

!ifndef MyAppVersion
  !define MyAppVersion "1.0.0"
!endif

!ifndef MySourceDir
  !error "MySourceDir must be provided."
!endif

!ifndef MyOutputDir
  !error "MyOutputDir must be provided."
!endif

!ifndef MyOutputBaseFilename
  !define MyOutputBaseFilename "EZVenera-setup"
!endif

!ifndef MySetupIconFile
  !define MySetupIconFile "..\windows\runner\resources\app_icon.ico"
!endif

Name "${MyAppName}"
OutFile "${MyOutputDir}\${MyOutputBaseFilename}.exe"
InstallDir "$PROGRAMFILES64\EZVenera"
InstallDirRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "InstallLocation"
RequestExecutionLevel admin
BrandingText " "
Icon "${MySetupIconFile}"
UninstallIcon "${MySetupIconFile}"
ShowInstDetails show
ShowUninstDetails show

!define MUI_ABORTWARNING
!define MUI_ICON "${MySetupIconFile}"
!define MUI_UNICON "${MySetupIconFile}"
!define MUI_FINISHPAGE_RUN "$INSTDIR\ezvenera.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch EZVenera"
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${MySourceDir}\*.*"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "DisplayName" "${MyAppName}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "DisplayVersion" "${MyAppVersion}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "Publisher" "${MyAppPublisher}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "DisplayIcon" "$INSTDIR\ezvenera.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "UninstallString" "$\"$INSTDIR\Uninstall.exe$\""
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}" "NoRepair" 1

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\EZVenera"
  CreateShortcut "$SMPROGRAMS\EZVenera\EZVenera.lnk" "$INSTDIR\ezvenera.exe"
  CreateShortcut "$DESKTOP\EZVenera.lnk" "$INSTDIR\ezvenera.exe"
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\EZVenera.lnk"
  Delete "$SMPROGRAMS\EZVenera\EZVenera.lnk"
  RMDir "$SMPROGRAMS\EZVenera"

  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\dartjni.dll"
  Delete "$INSTDIR\ezvenera.exe"
  Delete "$INSTDIR\file_selector_windows_plugin.dll"
  Delete "$INSTDIR\flutter_inappwebview_windows_plugin.dll"
  Delete "$INSTDIR\flutter_qjs_plugin.dll"
  Delete "$INSTDIR\flutter_windows.dll"
  Delete "$INSTDIR\native_assets.json"
  Delete "$INSTDIR\screen_retriever_windows_plugin.dll"
  Delete "$INSTDIR\sqlite3.dll"
  Delete "$INSTDIR\sqlite3_flutter_libs_plugin.dll"
  Delete "$INSTDIR\url_launcher_windows_plugin.dll"
  Delete "$INSTDIR\WebView2Loader.dll"
  Delete "$INSTDIR\window_manager_plugin.dll"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${MyAppName}"
SectionEnd
