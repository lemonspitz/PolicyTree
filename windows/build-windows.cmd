@echo off
rem Builds Policy Tree for Windows into dist\Policy-Tree-Windows.zip. Needs Python 3.11 or later from python.org.
setlocal
cd /d "%~dp0"
if not exist .venv-win py -3 -m venv .venv-win || python -m venv .venv-win
call .venv-win\Scripts\activate.bat
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
pyinstaller --noconfirm --clean policytree.spec
copy /y installer\Install.cmd "dist\Policy Tree\Install.cmd"
copy /y installer\Uninstall.cmd "dist\Policy Tree\Uninstall.cmd"
copy /y installer\INSTALL.txt "dist\Policy Tree\INSTALL.txt"
powershell -NoProfile -Command "Compress-Archive -Force -Path 'dist\Policy Tree' -DestinationPath 'dist\Policy-Tree-Windows.zip'"
echo Built dist\Policy-Tree-Windows.zip
