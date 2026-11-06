# Ms. Prissykins Pet & Feed

Give Ms. Prissykins some attention! Enable **Pet** and **Feed** in MySims Kingdom, with the game's own animations and sounds.

![Petting Ms. Prissykins at the top of the tower](docs/images/prissykins-petting-demo.gif)

## Download

**[Download v0.1.0](https://github.com/NekoCoaster/mysims-kingdom-ms-prissykins-pet-feed-patch/releases/download/v0.1.0/Prissykins-Petting-0.1.0.zip)**

For **Windows 64-bit, Steam build 21152538**. No extra software is needed on Windows 10 or 11. The helper checks your game version before making changes.

## Get started

1. Download and **extract the ZIP**. Keep its files together.
2. Close MySims Kingdom, then double-click **Install.cmd**.
3. Select `MySimsKingdom.exe` in your Steam game folder. To find it, right-click the game in Steam and choose **Manage > Browse local files**.
4. Start the game, load your save, and stand beside Ms. Prissykins. Wait until loading and any current action have finished.
5. Double-click **Enable Petting.cmd**, then return to the game to **Pet** or **Feed** her.

**Run Enable Petting.cmd again after restarting the game, reloading your save, or returning to the island.** You only need to install once per machine, and the helper can be closed afterwards.

Petting, feeding, and audio have been confirmed working after the tower quest.

## Good to know

- The helper does **not edit your saves**. The installer backs up the game script it changes; keeping your usual save backup is still a good idea.
- You can use it with another Steam account or computer. Install it on each machine; no save transfer is required.
- Run the helper while standing still beside her, **not during loading or an island transition**.
- If Windows denies access, right-click the relevant `.cmd` file and choose **Run as administrator**.
- If the helper reports an unsupported game version, check the [release page](https://github.com/NekoCoaster/mysims-kingdom-ms-prissykins-pet-feed-patch/releases) for an update.

## Uninstall

Close the game and run **Uninstall.cmd**. It restores the original script, provided you haven't edited that script since installing. Restarting the game clears the temporary interaction change.

## For developers

See [RESEARCH.md](RESEARCH.md) for technical details. Run `Build-Release.ps1` to build the ZIP and checksum. The repository includes Windows compilation and installer checks.

Unofficial community project, not affiliated with EA. The MIT license covers this project's source code, not the game or its assets.
