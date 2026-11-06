# Proxy DLL

`winmm.dll` forwards Windows multimedia exports to the original DLL loaded from the Windows system directory. The forwarding manifest includes the 181 named/ordinal exports on the development machine. Compatibility with other Windows versions still requires checking.

Only `MySimsKingdom.exe` with the supported SHA-256 starts the mod worker. Other hosts simply receive forwarding; unsupported game builds log a disabled message and receive forwarding without game-memory changes. The worker waits for a stable cat/island registration, adds the missing interaction handle using existing list capacity, and monitors only the cat's Pet/Feed sound groups. There is no Windows startup item, external resident helper, executable-code patch, or save-file access.

The game-folder `PrissykinsProxy.log` is replaced each launch. It records version acceptance, registration, and sound preparation. The DLL remains loaded until the game exits. The previous one-time `CatAnimal.lua` setting is still needed to permit interactions when she is not herded.

## Build

Use the official Zig 0.15.2 Windows x64 toolchain (download and SHA-256 from https://ziglang.org/download/index.json):

```powershell
.\native\Build-Proxy.ps1 -ZigPath C:\path\to\zig.exe
```

The generated forwarding assembly preserves integer, floating-point, and stack arguments during lazy resolution. `native/build/winmm.dll` is the output. The C++ support is linked into the DLL; Windows supplies the system C runtime.

Compile `test_logic.cpp` with the same compiler and `-lbcrypt` to run synthetic memory/layout checks. These do not substitute for a clean game startup and island-revisit test.

## Local installation / removal

Copy the built DLL beside `MySimsKingdom.exe`, only if that folder has no existing `winmm.dll`. Keep other mods' proxy DLLs intact. Start the game normally through Steam. Do not also launch the external sound helper.

To remove this proxy, close the game and remove only this project's `winmm.dll`. The existing script setting can separately be removed with the previous uninstaller. No game executable or sound banks are replaced.

## Limits

The registration and sound logic use the validated helper's guarded data edits from an in-process worker. A short stable-state delay reduces startup/transition risk but does not make concurrent game-list mutation race-free. Full-capacity interaction lists are left untouched. Voice polling can miss sounds shorter than the settling interval. The player confirmed automatic loading, interactions, and sound variation on a second computer. Before-quest behavior and island departure/return still need gameplay coverage.

## Checks

Run the synthetic tests without launching or attaching to the game:

```powershell
& C:\path\to\zig.exe c++ -target x86_64-windows-gnu -std=c++17 -O2 -static native/test_logic.cpp -lbcrypt -o native/build/test_logic.exe
& ./native/build/test_logic.exe
python -m pip install pefile
python native/test_forwarding.py
```

The forwarding test checks all 181 exports, concurrent first calls, timer and pointer arguments, and Windows-only runtime dependencies. `Build-Release.ps1` packages the DLL with the installer and player instructions, then verifies every ZIP entry against its source hash.
