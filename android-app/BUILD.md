# LispIM Android Build Instructions

## Current Status

The Android project structure is complete, but **Java/JDK is not installed** on this system. You need to install Java first before building.

## Option 1: Install JDK via Chocolatey (Recommended for Windows)

```powershell
# Open PowerShell as Administrator
choco install openjdk17 -y
```

Then set JAVA_HOME:
```powershell
setx JAVA_HOME "C:\Program Files\Eclipse Adoptium\jdk-17.0.x"
setx PATH "%JAVA_HOME%\bin;%PATH%"
```

## Option 2: Manual JDK Installation

1. Download JDK 17 from:
   - [Eclipse Adoptium Temurin](https://adoptium.net/temurin/releases/?version=17)
   - [Oracle JDK](https://www.oracle.com/java/technologies/downloads/#jdk17-windows)

2. Install to `C:\Program Files\Java\jdk-17`

3. Set environment variable:
   - Right-click "This PC" → Properties → Advanced system settings
   - Environment Variables → New (under System variables)
   - Variable name: `JAVA_HOME`
   - Variable value: `C:\Program Files\Java\jdk-17`

4. Add to PATH: `%JAVA_HOME%\bin`

## Verify Installation

```bash
java -version
javac -version
echo %JAVA_HOME%
```

## Build Commands

After Java is installed:

```bash
cd D:\VSCode\LispIM\android-app

# Debug build
gradlew.bat assembleDebug

# Release build
gradlew.bat assembleRelease

# Install on connected device
gradlew.bat installDebug

# Full clean build
gradlew.bat clean build
```

## Android SDK Setup

If you don't have Android SDK installed:

1. Download [Android Studio](https://developer.android.com/studio)
2. Install and open Android Studio
3. Go to Tools → SDK Manager
4. Install:
   - Android SDK Platform 34
   - Android SDK Build-Tools
   - Android SDK Command-line Tools

## Alternative: Use Android Studio

1. Open Android Studio
2. File → Open → Select `D:\VSCode\LispIM\android-app`
3. Wait for Gradle sync
4. Click Run (green play button) or Build → Build Bundle(s) / APK(s) → Build APK(s)

## Output Location

After successful build:
```
app/build/outputs/apk/debug/app-debug.apk
```

## Troubleshooting

### "JAVA_HOME not set"
```cmd
setx JAVA_HOME "C:\Program Files\Java\jdk-17"
```

### "SDK not found"
Create `local.properties` in project root:
```
sdk.dir=C\:\\Users\\YourUsername\\AppData\\Local\\Android\\Sdk
```

### "License not accepted"
```bash
gradlew.bat --init-script <(echo "allprojects { buildscript { repositories { maven { url 'https://plugins.gradle.org/m2/' } } } }") licenses
```

Or accept via Android Studio SDK Manager.
