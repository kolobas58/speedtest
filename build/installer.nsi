; Speedtest by kolobas58 — тихий установщик (без мастера и без UAC).
; Ставит портативный Speedtest.exe в %LOCALAPPDATA%\Programs\Speedtest, создаёт ярлыки
; и запись в «Программы и компоненты». Обновления приходят автоматически через сам Speedtest.exe.
; Ключи: /S — тихо (и так тихий), uninstall.exe /S — тихое удаление.
Unicode true
!include "FileFunc.nsh"

!ifndef VER
  !error "makensis -DVER=x.y.z -DEXE=Speedtest.exe -DOUT=file -DICON=file installer.nsi"
!endif

!define APP   "Speedtest"
!define UNKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Speedtest"

Name "Speedtest by kolobas58"
OutFile "${OUT}"
Icon "${ICON}"
UninstallIcon "${ICON}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
RequestExecutionLevel user
SilentInstall silent
SilentUnInstall silent
SetCompressor /SOLID lzma
ManifestDPIAware true
ManifestSupportedOS all

VIProductVersion "${VER}.0"
VIAddVersionKey "ProductName"      "Speedtest by kolobas58"
VIAddVersionKey "FileDescription"  "Speedtest by kolobas58 Setup"
VIAddVersionKey "CompanyName"      "kolobas58"
VIAddVersionKey "LegalCopyright"   "(c) kolobas58"
VIAddVersionKey "FileVersion"      "${VER}"
VIAddVersionKey "ProductVersion"   "${VER}"
VIAddVersionKey "OriginalFilename" "Speedtest-Setup.exe"

!macro StopApp
  ; закрыть запущенный Speedtest (его рантайм живёт в %LOCALAPPDATA%\Speedtest)
  nsExec::Exec 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process pythonw -ErrorAction SilentlyContinue | Where-Object { $$_.Path -like \"$LOCALAPPDATA\Speedtest\*\" } | Stop-Process -Force"'
  Pop $0
!macroend

Section "Install"
  !insertmacro StopApp
  SetOutPath "$INSTDIR"
  Delete "$INSTDIR\Speedtest.exe.old"
  File "/oname=Speedtest.exe" "${EXE}"
  File "/oname=speedtest.ico" "${ICON}"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  SetShellVarContext current
  CreateShortCut "$DESKTOP\${APP}.lnk"    "$INSTDIR\Speedtest.exe" "" "$INSTDIR\speedtest.ico" 0 SW_SHOWNORMAL "" "Speedtest by kolobas58"
  CreateShortCut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\Speedtest.exe" "" "$INSTDIR\speedtest.ico" 0 SW_SHOWNORMAL "" "Speedtest by kolobas58"

  WriteRegStr   HKCU "${UNKEY}" "DisplayName"          "Speedtest by kolobas58"
  WriteRegStr   HKCU "${UNKEY}" "DisplayVersion"       "${VER}"
  WriteRegStr   HKCU "${UNKEY}" "Publisher"            "kolobas58"
  WriteRegStr   HKCU "${UNKEY}" "DisplayIcon"          "$INSTDIR\speedtest.ico"
  WriteRegStr   HKCU "${UNKEY}" "InstallLocation"      "$INSTDIR"
  WriteRegStr   HKCU "${UNKEY}" "UninstallString"      '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKCU "${UNKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNKEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNKEY}" "EstimatedSize" 46000
SectionEnd

Section "Uninstall"
  !insertmacro StopApp
  Sleep 500
  SetShellVarContext current
  Delete "$DESKTOP\${APP}.lnk"
  Delete "$SMPROGRAMS\${APP}.lnk"
  RMDir /r "$INSTDIR"
  RMDir /r "$LOCALAPPDATA\Speedtest"     ; кэш рантайма и настройки
  DeleteRegKey HKCU "${UNKEY}"
SectionEnd
