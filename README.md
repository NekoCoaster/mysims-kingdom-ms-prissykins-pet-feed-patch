# Ms. Prissykins Pet & Feed

Give Ms. Prissykins some attention! Enable **Pet** and **Feed** in MySims Kingdom, with the game's own animations and alternating sound recordings.

![Petting Ms. Prissykins at the top of the tower](docs/images/prissykins-petting-demo.gif)

**[Download v0.2.0](https://github.com/NekoCoaster/mysims-kingdom-ms-prissykins-pet-feed-patch/releases/download/v0.2.0/Prissykins-Petting-0.2.0.zip)**

For **Windows 64-bit, Steam build 21152538**. The mod checks your game version before enabling its changes.

## Install once, then play normally

1. Close MySims Kingdom. Download and extract the ZIP.
2. In Steam, right-click MySims Kingdom and choose **Manage > Browse local files**.
3. Copy **winmm.dll** from the ZIP into that folder, beside **MySimsKingdom.exe**. If another mod already installed a file with that name, don't overwrite it.
4. Double-click **Install.cmd** in the extracted download and select **MySimsKingdom.exe**. This sets up the game script once and backs up the original.
5. Start the game normally through Steam, load your save, and approach Ms. Prissykins. Allow a few seconds for **Pet** and **Feed** to appear.

**That's it—no helper window or CMD file to run each time you play.** The mod loads with the game and stops when the game closes. Pet/Feed and sound variation have been confirmed working after the tower quest, including on a second computer.

### Updating from v0.1.0

Close the game and copy the new **winmm.dll** beside **MySimsKingdom.exe**. Your existing script setting can stay as it is. Stop using **Enable Petting.cmd** and **Enable Varied Sounds.cmd**; they are no longer needed.

## Good to know

- The mod does **not edit your saves** and is not tied to a Steam account. Install it separately on each computer.
- If Windows denies access during the one-time script setup, right-click **Install.cmd** and choose **Run as administrator**.
- If a game update stops it working, check the [release page](https://github.com/NekoCoaster/mysims-kingdom-ms-prissykins-pet-feed-patch/releases). Steam's file verification may also reset the script setting; run **Install.cmd** again if needed.
- For troubleshooting, look for **PrissykinsProxy.log** in the game folder. It is refreshed each launch.

## Uninstall

Close the game, delete this mod's **winmm.dll** from the game folder, then run **Uninstall.cmd** from the extracted download to restore the original script. The uninstaller preserves later script edits and settings you added yourself.

## For developers

See [native/README.md](native/README.md) for the DLL build and checks, and [RESEARCH.md](RESEARCH.md) for the investigation. Build the DLL first, then run `Build-Release.ps1` to package it. The older external helper remains in the source repository for reference; it is not included in the v0.2.0 player download.

Unofficial community project, not affiliated with EA. The MIT license covers this project's source code, not the game or its assets.
