@echo off
if not exist cclite-latest-beta.love goto makeArchive
set /P replace=Overwrite cclite-latest-beta.love [Y/N]: 
if /I NOT %replace%==Y goto end
del cclite-latest-beta.love
:makeArchive
cd src
..\7za.exe a -r -tzip -mx5 ..\cclite-latest-beta.love ".\*"
cd ..
:end
pause