@echo off
rem Removes the shortcuts and file association. Your saved trees are not touched.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "foreach ($dir in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {" ^
  "  Remove-Item -ErrorAction SilentlyContinue (Join-Path $dir 'Policy Tree.lnk') }"
reg delete "HKCU\Software\Classes\.policytree" /f >nul 2>&1
reg delete "HKCU\Software\Classes\PolicyTree.Document" /f >nul 2>&1
echo Pintasan dan pengaitan berkas sudah dihapus. Sekarang folder ini boleh dihapus.
pause
