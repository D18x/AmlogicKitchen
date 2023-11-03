@echo off

:: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
:--------------------------------------

setlocal EnableDelayedExpansion

cls


goto level
:level

echo .....................
echo Amlogic Kitchen
echo .....................
set /P level=Select level 1,2,3 or q/Q to exit: 
IF %level% == 1 GOTO level1
IF %level% == 2 GOTO level2
IF %level% == 3 GOTO level3
IF %level% == q exit
IF %level% == Q exit
ELSE goto level

:level1

if exist level1 rmdir /q /s level1
md level1

echo .....................
echo Amlogic Kitchen
echo .....................
echo Files in input dir (*.img)
if not exist in\*.img (
  echo Can't find images
  if not exist in\ (
    mkdir in
  )
  pause
  exit 0
)

SET /A COUNT=0
for %%a in (in\*.img) do set /a count += 1 && echo !count! - %%~na
echo .....................
set /P projectname=Enter a file name :
echo %projectname%> level1\projectname.txt

if not exist in\%projectname%.img (
echo Can't find the file
pause
exit 0
)

set /p filename=< level1\projectname.txt

bin\windows\AmlImagePack -d "in\%filename%.img" level1

goto level


:level2
rem Tested with Python 3.11.6
py --version 2>NUL
if errorlevel 1 (
echo Error^: Python not installed
pause
exit
)

if exist level1 goto pass2
echo Unpack level 1 first
pause
exit

:pass2

if exist level2 rmdir /q /s level2
md level2\config\

echo .....................
echo choose a method to unpack firmware
echo some newer/older firmwares doesn't work properly
echo retry with different version if you have issues
echo For super image we will use python for unpacking
echo .....................
echo 1 - vortex
echo 2 - python
echo .....................
set /P extracttype=Enter a number :
if !extracttype! EQU 1 (
    FOR %%A IN (odm oem product vendor system system_ext odm_ext_a odm_ext_b) DO (
    if exist level1\%%A.PARTITION (
        bin\windows\imgextractor level1\%%A.PARTITION level2\%%A
        move level2\%%A_size level2\config\%%A_size.txt
        move level2\%%A_* level2\config\
        if exist level1\%%A.raw.img (
            del level1\%%A.raw.img
        )
    )
    )
) else (
    FOR %%A IN (odm oem product vendor system system_ext odm_ext_a odm_ext_b) DO (
    if exist level1\%%A.PARTITION (
        bin\windows\file level1\%%A.PARTITION | findstr /C:"sparse">nul && (
            bin\windows\simg2img level1\%%A.PARTITION level2\%%A.img
            py bin\common\imgextractor.py "level2\%%A.img" "level2"
        ) || (
            py bin\common\imgextractor.py "level1\%%A.PARTITION" "level2"
        )
        if exist level1\%%A.raw.img (
            del level1\%%A.raw.img
        )
        if exist level2\config\%%A_file_contexts (
            bin\windows\sed -n "G; s/\n/&&/; /^\([ -~]*\n\).*\n\1/d; s/\n//; h; P" level2\config\%%A_file_contexts > level2\config\%%A_sorted_file_contexts
            move level2\config\%%A_sorted_file_contexts level2\config\%%A_file_contexts
        )
    )
    )
)

if exist level1\super.PARTITION (
    bin\windows\simg2img level1\super.PARTITION level2\super.img
    bin\windows\du -sb level2\super.img | bin\windows\cut -f1> level2\config\super_size.txt
    bin\windows\super\lpunpack -slot=0 level2\super.img level2\
    del level2\super.img

    FOR %%A IN (system_a system_ext_a vendor_a product_a odm_a system_b system_ext_b vendor_b product_b odm_b) DO (
    if exist level2\%%A.img (
        call :setsize level2\%%A.img
        if !size! GTR 1024 (
            py bin\common\imgextractor.py "level2\%%A.img" "level2"
        )
        if exist level2\config\%%A_file_contexts (
            bin\windows\sed -n "G; s/\n/&&/; /^\([ -~]*\n\).*\n\1/d; s/\n//; h; P" level2\config\%%A_file_contexts > level2\config\%%A_sorted_file_contexts
            move level2\config\%%A_sorted_file_contexts level2\config\%%A_file_contexts
        )
    )
    )
) else (
goto level
)

set cnt=0
for %%A in (level2\*_a.img) do set /a cnt+=1
if exist level1\super.PARTITION (
    echo %cnt%
    if %cnt% GTR 0 (
        echo 3 > level2\config\super_type.txt
    ) else (
        echo 2 > level2\config\super_type.txt
    )
)

:setsize
set size=%~z1
goto :eof

echo Done.
goto level

:level3

if exist level1 goto pass3
echo Unpack level 1 first
pause
exit

:pass3

if exist level3 rmdir /q /s level3
md level3 level3\boot level3\boot_a level3\recovery level3\recovery_a level3\logo level3\devtree level3\meson1

FOR %%A IN (recovery boot recovery_a boot_a) DO (
    if exist level1\%%A.PARTITION (
        copy level1\%%A.PARTITION bin\windows\aik\%%A.img
        call bin\windows\aik\unpackimg.bat bin\windows\aik\%%A.img
        if exist bin\windows\aik\ramdisk\ (
            move bin\windows\aik\ramdisk level3\%%A\
        )
        move bin\windows\aik\split_img level3\%%A\
        del bin\windows\aik\%%A.img
    )
)

if exist level1\logo.PARTITION (
    bin\windows\imgpack -d level1\logo.PARTITION level3\logo
)

:: i dont have no idea to simplify this
if not exist level1\_aml_dtb.PARTITION (
    if exist level3\boot\split_img\boot.img-dtb (
        copy level3\boot\split_img\boot.img-dtb level1\_aml_dtb.PARTITION
    ) else if exist level3\boot_a\split_img\boot_a.img-dtb (
        copy level3\boot_a\split_img\boot_a.img-dtb level1\_aml_dtb.PARTITION
    ) else if exist level3\boot\split_img\boot.img-second (
        copy level3\boot\split_img\boot.img-second level1\_aml_dtb.PARTITION
    ) else if exist level3\boot_a\split_img\boot_a.img-second (
        copy level3\boot_a\split_img\boot_a.img-second level1\_aml_dtb.PARTITION
    ) else if exist level3\recovery\split_img\recovery.img-dtb (
        copy level3\recovery\split_img\recovery.img-dtb level1\_aml_dtb.PARTITION
    ) else if exist level3\recovery_a\split_img\recovery_a.img-dtb (
        copy level3\recovery_a\split_img\recovery_a.img-dtb level1\_aml_dtb.PARTITION
    ) else if exist level3\recovery\split_img\recovery.img-second (
        copy level3\recovery\split_img\recovery.img-second level1\_aml_dtb.PARTITION
    ) else if exist level3\recovery_a\split_img\recovery_a.img-second (
        copy level3\recovery_a\split_img\recovery_a.img-second level1\_aml_dtb.PARTITION
    )
)

bin\windows\dtc -I dtb -O dts -o level3\devtree\single.dts level1\_aml_dtb.PARTITION
bin\windows\7za x level1\_aml_dtb.PARTITION -y > NUL:
bin\windows\dtbSplit level1\_aml_dtb.PARTITION level3\devtree\

if exist level1\meson1.dtb (
    bin\windows\dtbSplit level1\meson1.dtb level3\meson1\
)

if exist _aml_dtb (
    bin\windows\dtbSplit _aml_dtb level3\devtree\
    del _aml_dtb
)

for %%x in (level3\devtree\*.dtb) do (
    bin\windows\dtc -I dtb -O dts -o level3\devtree\%%~nx.dts %%x
    del %%x
)

for %%x in (level3\meson1\*.dtb) do (
    bin\windows\dtc -I dtb -O dts -o level3\meson1\%%~nx.dts %%x
    del %%x
)

ROBOCOPY level3 level3 /S /MOVE /NFL /NDL /NJH /NJS /nc /ns /np

echo Done.
goto level
