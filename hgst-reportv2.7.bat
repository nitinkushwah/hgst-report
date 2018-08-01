@echo off
REM Author: CTS GSS
REM JBOD Log gathering for Windows
REM V2.7
set VERSION=2.7
REM History: v2.7 20th July 2018: fixed bug for multiple ESM logs collection
REM History: v2.6 18th May 2018: removed makecab as it fails under some conditions.
REM History: v2.5 10th May 2018: Added Megaraid storcli commands
REM History: v2.4 21st Mar 2018: Clean directory structure, 60 days of windows logs
REM History: v2.3 19th Mar 2018: Added support for SMART
REM History: v2.2 19th Mar 2018: Added support for hgst_diag_tool and hdm
REM History: 16th Mar 2018: Added system information logs,msinfo(driver), suppressed error for page EA
REM History: 14th Mar 2018: Script can now collect logs from more than 2 ESMs
REM History: 14th Mar 2018: Added windows system and application log collection
REM History:8th Mar 2018: added automatic scanning the ESM ID 
REM History:8th Mar 2018: added E6 raw page collection
REM


echo Script Version : %VERSION%
::If 3rd param is blank then scan for ESMs
IF [%3]==[] GOTO Magicscan

::If 3rd param is present then set all param without scanning
IF NOT [%3]==[] (
set ESMA=%1
set ESMB=%2
set DIR=%3
GOTO Run
)


:Magicscan
setlocal enabledelayedexpansion
set COUNT=0
echo "Scannning ESMs....."

for /f "tokens=1" %%i in ('sg_scan -s ^| findstr -i "4U60 4U102 2u 4u peak madonna scaleapex H4102 H4060"') do (
  set "INPUT=%%i"
  set /A COUNT=!COUNT!+1
  set "INPUT=!INPUT:DATA:=!"
  set VAR[!COUNT!]=!INPUT!
  call echo ESM !COUNT! = %%VAR[!COUNT!]%%

)


REM IF [%1]==[] GOTO Syntax

REM set ESMA="%VAR[1]%"

REM IF NOT DEFINED VAR[2] (SET VAR[2]=NA) 
REM set ESMB="%VAR[2]%"
REM set DIR=%1
set DIR="%1\logs_%COMPUTERNAME%_%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%time:~-11,2%%time:~-8,2%%time:~-5,2%"

:Run
WHERE sg_scan >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO ses
IF %ERRORLEVEL% EQU 1 GOTO Missing

:ses
WHERE sg_ses >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO inq
IF %ERRORLEVEL% EQU 1 GOTO Missing

:inq
WHERE sg_inq >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO Gather
IF %ERRORLEVEL% EQU 1 GOTO Missing


:Gather

mkdir %DIR%\winlogs





echo Script Version: %VERSION% > %DIR%\ver.txt
echo. >> %DIR%\ver.txt
echo sg_scan: >> %DIR%\ver.txt
sg_scan -V 2>> %DIR%\ver.txt
echo. >> %DIR%\ver.txt
echo sg_ses: >> %DIR%\ver.txt
sg_ses -V 2>> %DIR%\ver.txt

mkdir %DIR%\esm

sg_scan -s >> %DIR%\esm\SG_SCAN.txt
echo ______________________ >> %DIR%\esm\SG_SCAN.txt
for /l %%n in (1,1,%COUNT%) do (
echo ESM%%n  !VAR[%%n]! >> %DIR%\esm\SG_SCAN.txt
)



::Collecting System Information
echo Collecting System Information.....
ECHO.
ECHO.
ECHO If log capture appears hang please press Enter key....
ECHO.
ECHO.
systeminfo >%DIR%\winlogs\systeminfo.txt
msinfo32 /report %DIR%\winlogs\msinfo.txt
echo Collecting System Events.....
wevtutil qe System /q:"*[System[TimeCreated[timediff(@SystemTime) <= 7776000000]]]"  /rd:True /f:text >%DIR%\winlogs\system_event.txt
echo Collecting Application Events......
wevtutil qe Application /q:"*[System[TimeCreated[timediff(@SystemTime) <= 7776000000]]]" /rd:True /f:text >%DIR%\winlogs\Application_events.txt


WHERE hgst_diag_tool.exe >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO HGSTtools
IF %ERRORLEVEL% EQU 1 GOTO NoHGSTtools

:HGSTtools
echo Collecting HGST diag logs......
mkdir %DIR%\hgstlogs

for /l %%n in (1,1,%COUNT%) do (
hgst_diag_tool.exe -d !VAR[%%n]! -n
move diag_dump_*.dat %DIR%\hgstlogs\
)

:NoHGSTtools

WHERE smartctl.exe >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO SMART
IF %ERRORLEVEL% EQU 1 GOTO NoSMART

:SMART
echo Collecting SMART logs......
mkdir %DIR%\smartlogs

smartctl.exe --scan > %DIR%\smartlogs\smart_scan.txt


for /f "tokens=1" %%i in ('smartctl.exe --scan') do (
echo %%i >> %DIR%\smartlogs\smart_health.txt
smartctl.exe -H %%i >> %DIR%\smartlogs\smart_health.txt
smartctl.exe -x %%i >> %DIR%\smartlogs\smart_extended.txt
)


:NoSMART

WHERE hdm.exe >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO HDM
IF %ERRORLEVEL% EQU 1 GOTO NoHDM

:HDM
echo Collecting HDM logs......
mkdir %DIR%\hdm

hdm generate-report >> %DIR%\hdm\hdm_report.txt

:NoHDM


WHERE storcli.exe >nul 2>nul
IF %ERRORLEVEL% EQU 0 GOTO Storcli
IF %ERRORLEVEL% EQU 1 GOTO NoStorcli
:Storcli
echo Collecting Storcli logs......
mkdir %DIR%\storcli

storcli /c0/eAll/sAll show all>> %DIR%\storcli\c0_eAll_sAll.txt
storcli /c0 show all >> %DIR%\storcli\show_all.txt
storcli /c0 show termlog >> %DIR%\storcli\termlog.txt
storcli /c0 show events filter=warning,critical,fatal >>%DIR%\storcli\events.txt 2>nul 

REM collecting only 500 info events else script fails to compress it (possibly a bug)
storcli /c0 show events type=latest=500 filter=info  >>%DIR%\storcli\events_info.txt 2>nul 

:NoStorcli




for /l %%n in (1,1,%COUNT%) do (

mkdir %DIR%\ESM%%n

echo Collecting logs for : ESM%%n  !VAR[%%n]! ......

sg_ses !VAR[%%n]! -p0x0 >> %DIR%\ESM%%n\page_00h.txt

sg_ses !VAR[%%n]! -p0x1 >> %DIR%\ESM%%n\page_01h.txt

sg_ses !VAR[%%n]! -p0x2 >> %DIR%\ESM%%n\page_02h.txt

sg_ses !VAR[%%n]! -p0x3 >> %DIR%\ESM%%n\page_03h.txt

sg_ses !VAR[%%n]! -p0x5 >> %DIR%\ESM%%n\page_05h.txt

sg_ses !VAR[%%n]! -p0x7 >> %DIR%\ESM%%n\page_07h.txt

sg_ses !VAR[%%n]! -p0xA >> %DIR%\ESM%%n\page_0Ah.txt

sg_ses !VAR[%%n]! -p0xEA >> %DIR%\ESM%%n\page_EAh.txt 2>nul

sg_ses !VAR[%%n]! -jj >> %DIR%\ESM%%n\join.txt

sg_inq !VAR[%%n]! >> %DIR%\ESM%%n\inq.txt

sg_inq !VAR[%%n]! -p0x83 >> %DIR%\ESM%%n\inq_83h.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 00 01 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\console_log.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 01 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\console_log.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 02 01 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\console_log.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 00 02 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_primary.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 00 02 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_primary.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 00 02 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_primary.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 01 02 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary1.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 02 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary1.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 02 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary1.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 02 02 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary2.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 02 02 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary2.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 02 02 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\crashlog_secondary2.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 00 03 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_primary.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 00 03 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_primary.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 00 03 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_primary.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary1.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary1.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary1.txt

sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 00 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary2.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 20 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary2.txt
sg_raw !VAR[%%n]! -r 0x4000 E6 01 03 00 40 00 00 20 10 00 2>> %DIR%\ESM%%n\eventlog_secondary2.txt

)


cd %DIR%


GOTO Package

:Syntax
ECHO.
ECHO Please specify the destination for logs files.
ECHO.
GOTO End

:Package
ECHO.
ECHO.
ECHO Provide the logs %DIR% created to support for further analysis.
ECHO.
GOTO End

:Missing
ECHO.
ECHO One or more of the required utilities are not recognized as Internal or External commands - 'sg_scan' 'sg_ses' 'sg_inq'
ECHO.  
GOTO End

:End


