; Speedtest by kolobas58 — портативный стартер: один exe без установки.
; Первый запуск распаковывает рантайм в %LOCALAPPDATA%\Speedtest\app-<версия> (~2 c),
; следующие — запускают сразу. Старые версии удаляются автоматически.
Unicode true

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
VIAddVersionKey "OriginalFilename" "Speedtest.exe"

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
  SetOutPath "$DIR"
  Exec '"$DIR\python\pythonw.exe" -E -s "$DIR\speedtest.pyw" --exe "$EXEPATH"'
SectionEnd
