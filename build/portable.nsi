; Speedtest by kolobas58 — портативный стартер: один exe без установки.
; Первый запуск распаковывает рантайм в %LOCALAPPDATA%\Speedtest\app-<версия> (~2 c),
; следующие — запускают сразу. Старые версии удаляются автоматически.
; 2.x: Windows 10/11 — Flutter-версия (app\speedtest.exe), Windows 7/8 — прежняя на Python/Qt5 (legacy\).
Unicode true
!include "LogicLib.nsh"
!include "WinVer.nsh"

!ifndef VER
  !error "makensis -DVER=x.y.z -DPAYLOAD=dir -DOUT=file -DICON=file portable.nsi"
!endif

Name "Speedtest by kolobas58"
OutFile "${OUT}"
Icon "${ICON}"
RequestExecutionLevel user
SilentInstall silent
SetCompressor /SOLID lzma
SetCompressorDictSize 32
ManifestDPIAware true
ManifestSupportedOS all

VIProductVersion "${VER}.0"
VIAddVersionKey "ProductName"      "Speedtest by kolobas58"
VIAddVersionKey "FileDescription"  "Speedtest by kolobas58"
VIAddVersionKey "CompanyName"      "kolobas58"
VIAddVersionKey "LegalCopyright"   "(c) kolobas58"
VIAddVersionKey "FileVersion"      "${VER}"
VIAddVersionKey "ProductVersion"   "${VER}"
VIAddVersionKey "OriginalFilename" "Speedtest-Portable.exe"

Var DIR

Section
  StrCpy $DIR "$LOCALAPPDATA\Speedtest\app-${VER}"
  IfFileExists "$DIR\.ready" launch

  RMDir /r "$DIR"                 ; недораспакованная копия (если прошлый запуск прервали)
  SetOutPath "$DIR"
  File /r "${PAYLOAD}/*"
  FileOpen $0 "$DIR\.ready" w
  FileClose $0

  ; удалить прошлые версии
  FindFirst $1 $2 "$LOCALAPPDATA\Speedtest\app-*"
  loop:
    StrCmp $2 "" done
    StrCmp $2 "app-${VER}" next
    RMDir /r "$LOCALAPPDATA\Speedtest\$2"
  next:
    FindNext $1 $2
    Goto loop
  done:
  FindClose $1

  launch:
  ${If} ${AtLeastWin10}
    SetOutPath "$DIR\app"
    Exec '"$DIR\app\speedtest.exe" --exe "$EXEPATH"'
  ${Else}
    SetOutPath "$DIR\legacy"
    Exec '"$DIR\legacy\python\pythonw.exe" -E -s "$DIR\legacy\speedtest.pyw" --exe "$EXEPATH"'
  ${EndIf}
SectionEnd
