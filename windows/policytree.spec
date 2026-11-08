# PyInstaller recipe: builds dist/Policy Tree/Policy Tree.exe.
import os
here = os.path.abspath(SPECPATH)

a = Analysis(
    [os.path.join(here, 'run.py')],
    pathex=[here],
    datas=[(os.path.join(here, 'policytree', 'icon.png'), 'policytree'),
           (os.path.join(here, 'policytree', 'strings_en.json'), 'policytree'),
           (os.path.join(here, 'installer', 'THIRD-PARTY.md'), '.')],
    excludes=['tkinter', 'PySide6.QtNetwork', 'PySide6.QtQml', 'PySide6.QtQuick', 'PySide6.QtDBus'],
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='Policy Tree', console=False,
          icon=os.path.join(here, 'policytree', 'icon.ico'),
          version=os.path.join(here, 'installer', 'version.txt'))
coll = COLLECT(exe, a.binaries, a.datas, name='Policy Tree')
