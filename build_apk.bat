@echo off
cd /d d:\Project\betterme
flutter build apk --release
echo BUILD DONE - Exit code: %ERRORLEVEL%
pause
