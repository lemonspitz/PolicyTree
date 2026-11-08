@echo off
rem Adds Policy Tree to the Start menu and desktop, and opens .policytree files with it.
rem Needs no administrator rights. Run it again if you move this folder.
setlocal
if not exist "%~dp0Policy Tree.exe" (
  echo Jalankan dari folder "Policy Tree" yang sudah diekstrak, di samping "Policy Tree.exe".
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell;" ^
  "foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {" ^
  "  $s = $ws.CreateShortcut((Join-Path $dir 'Policy Tree.lnk'));" ^
  "  $s.TargetPath = '%~dp0Policy Tree.exe';" ^
  "  $s.WorkingDirectory = '%~dp0';" ^
  "  $s.Description = 'Policy Tree';" ^
  "  $s.Save() }"
if errorlevel 1 echo Pintasan tidak bisa dibuat. Aplikasi tetap bisa dibuka dari "Policy Tree.exe".

set "EXE=%~dp0Policy Tree.exe"
reg add "HKCU\Software\Classes\.policytree" /ve /d "PolicyTree.Document" /f >nul
reg add "HKCU\Software\Classes\PolicyTree.Document" /ve /d "Policy Tree" /f >nul
reg add "HKCU\Software\Classes\PolicyTree.Document\DefaultIcon" /ve /d "\"%EXE%\",0" /f >nul
reg add "HKCU\Software\Classes\PolicyTree.Document\shell\open\command" /ve /d "\"%EXE%\" \"%%1\"" /f >nul
echo Policy Tree sudah ada di menu Start dan desktop.
pause
