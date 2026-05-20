@echo off
setlocal
echo JAVA_HOME=%JAVA_HOME%
for %%d in ("C:\Program Files\Java\*" "C:\Program Files\Android\Android Studio\jbr" "C:\Users\user\AppData\Local\Programs\Android Studio\jbr") do (
    if exist "%%~d\bin\java.exe" (
        echo FOUND: %%~d\bin\java.exe
    )
)
where java.exe 2>nul
