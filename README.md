# Ms. Prissykins Pet & Feed

In the **ferry travel prerelease**, Ms. Prissykins can follow you to another island. After Renée's tower quest, **Feed** her to invite her along. She'll meet you after the ferry docks. **Pet** asks her to stay as soon as the interaction starts, even when it drops no mana.

Ferry travel has been tested between the Nature Preserve (Renée's island) and Capital Island. Other islands are still untested.

## Install

For **Windows 64-bit, Steam build 21152538**.

1. Close MySims Kingdom. Back up your Steam account folder under `%LOCALAPPDATA%\Electronic Arts\MySimsKingdom\Steam`, then extract the ZIP.
2. In Steam, right-click **MySims Kingdom** and choose **Manage > Browse local files**.
3. Run **Install.cmd** from the extracted folder and select **MySimsKingdom.exe**. It installs both files and can upgrade v0.2.0 and v0.3.0. If another mod uses **winmm.dll**, setup leaves it in place. If Windows denies access, use **Run as administrator**.
4. Start the game normally through Steam.

Travel lasts for the current play session. If you ask her to stay on an away island and then leave, her visit ends and you can find her again at the Nature Preserve. When she follows you back to the Nature Preserve, the game can save her new position there.

If travel fails, check **PrissykinsProxy.log** in the game folder.

## Roll back

Close the game, remove this prerelease's **winmm.dll**, and run **Uninstall.cmd** from this ZIP to restore your backed-up game script. To return to v0.3.0, copy **winmm.dll** from the v0.3.0 ZIP beside the game and run that version's **Install.cmd**.

Unofficial community mod for MySims Kingdom.
