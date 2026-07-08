# my_app

Immersive workout timer built with Flutter.

## Run Targets

Run the app from `lib/main.dart`. The app starts on a home screen and navigates into the workout timer from there.

### Windows

Prerequisites for a clean Windows setup:

- Enable Windows Developer Mode so Flutter plugins can create symlinks.
- Install the NuGet CLI, for example with `winget install --id Microsoft.NuGet`.
- Use Visual Studio with desktop C++ support.

Run the app with:

```powershell
flutter run -d windows
```

Notes:

- The Windows CMake setup is pinned to build into the local Flutter output folder rather than `C:\Program Files`.
- Voice cues are disabled on Windows because the current `flutter_tts` Windows plugin path is unstable in this project.

### Android Emulator

This workspace is configured to use a Pixel 5 emulator with the id `Pixel_5`.

Launch it with:

```powershell
flutter emulators --launch Pixel_5
```

Then confirm it is online:

```powershell
flutter devices
```

When the emulator is listed as a connected Android device, run:

```powershell
flutter run -d emulator-5554
```
