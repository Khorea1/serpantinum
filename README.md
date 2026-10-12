<div align="center">
  <a href="https://ko-fi.com/ilyamiro">
    <img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="ko-fi" />
  </a>
</div>

<div align="center">
  <img src="docs/assets/banner.png" alt="Serpantinum" width="850" />
</div>

## Previews

| | |
|---|---|
| ![Preview 1](docs/assets/previews/preview_1.png) | ![Preview 2](docs/assets/previews/preview_2.png) |
| ![Preview 3](docs/assets/previews/preview_3.png) | ![Preview 4](docs/assets/previews/preview_4.png) |

---

## Fork differences

This fork builds on the original [Serpantinum](https://github.com/ilyamiro/serpantinum). The baseline below is upstream commit [8c3ea64566e0a277bdf44065a6c489a850572875](https://github.com/ilyamiro/serpantinum/commit/8c3ea64566e0a277bdf44065a6c489a850572875), last incorporated into this fork on October 8, 2026. Upstream has continued to evolve since then, so these differences describe the fork relative to that shared baseline, not necessarily to upstream's current tip.

| Area | Upstream baseline | This fork |
|---|---|---|
| Symbol picker | No unified emoji/glyph/kaomoji picker in this revision. | Adds emoji, Nerd Font glyph, and kaomoji tabs with search, category navigation, direct typing (`Alt+Enter`), and recently/frequently used symbols prioritized within the results. Category chips scroll to keep the active category visible. See the [picker source](src/quickshell/emoji/Emoji.qml). |
| Window picker | No dedicated window picker in this revision. | Adds a searchable window picker alongside the other popup tools. See [PickWindow.qml](src/quickshell/pickwindow/PickWindow.qml). |
| Window overview | No thumbnail overview in this revision. | Adds an optional Hyprland-only `expose` bar module with previews of open windows across workspaces. It is hidden on Niri and Sway and leaves the searchable window picker and workspace indicators intact. Adapted from [Mustafa2624/serpantinum-plus](https://github.com/Mustafa2624/serpantinum-plus/tree/1a4d80b9025fb6423008fb77ea8a41a9feeb2292/custom/overlay/src/quickshell/bar/faces/expose). |
| Popup navigation | Launcher and clipboard are separate popups. | Adds a shared switcher for launcher, symbols, clipboard, and window picker, accessible through on-screen buttons or `Ctrl+H/L`. The symbol picker's categories use `Alt+H/L`. See [SelectorSwitcher.qml](src/quickshell/reusables/behavior/SelectorSwitcher.qml). |
| Notifications | Already includes notifications and a Notification Center. | Extends the existing center with text, app, and date filters; grouped history; unread tracking; bulk, per-item, and group dismissal; and timed Do Not Disturb snoozes. See [NotificationCenter.qml](src/quickshell/notifications/NotificationCenter.qml). |
| Fonts | Discovers bundled fonts and files in Serpantinum's user-state directory. | Adds system fonts through Fontconfig alongside fonts in the user-state directory; selected font files are still loaded by the shell. See [ThemeBackend.qml](src/quickshell/singletons/theme/ThemeBackend.qml). |
| Wallpapers | Uses the QML wallpaper surface. | Adds optional `wallpaperBackend = "awww"` for static images. QML remains the default backend and continues to handle video wallpapers. See [Wallpaper.qml](src/quickshell/singletons/theme/Wallpaper.qml). |
| Bar and widgets | Includes workspace indicators and a media widget. | Refines workspace and widget transitions, uses square workspace indicators, and collapses the media widget when there is no active media. The focused-window widget displays the current window title only, hides when the desktop is focused or the title is empty, and updates on Hyprland window-title changes. See [CurrentFocus.qml](src/quickshell/singletons/system/CurrentFocus.qml) and [current_focus.sh](src/scripts/current_focus.sh). |
| Multi-monitor behavior | Popup screen selection uses the compositor-specific path. | Adds a Wayland active-toplevel screen fallback for launcher, symbols, clipboard, and window picker, with the first available screen as a final fallback. |

> [!NOTE]
> The installation instructions below still select the original upstream repository: the Arch command downloads its installer, the Nix flake input is `github:ilyamiro/serpantinum`, and the installer defaults to `ilyamiro/serpantinum`. They do not install this fork.

On Hyprland, open **Guide → Bar → Modules** and drag **Window overview** from the available modules into the bar layout, or add `"expose"` to your bar's configured module list. It is opt-in and will not appear in existing bar layouts until enabled. Click it to view window previews, use the arrow keys to navigate, press Enter to focus the selection, or Escape to close. The overview needs Quickshell's Wayland screencopy capability and `hyprctl` for activation. It never edits compositor keybindings or starts automatically.

---

## Installation

> [!IMPORTANT]
> **Migrating from v1:** All previous configuration will be backed up and unused. Configuration of compositor settings such as monitors, keybinds, and autostart is now up to you, as the project migrated from being dotfiles to being a shell.

### Arch Linux and its derivatives

For Arch-based distributions (including systemd, OpenRC, and other init systems), run the automated installation script.:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ilyamiro/serpantinum/master/install/install.sh)"

```

> [!NOTE]
> To update, when or if you recieve a notification about the new version being available, just run the script again and choose "update"

---

### NixOS

Serpantinum provides flake outputs, a NixOS module for system dependencies, and a Home Manager module for user configuration and service management.

#### 1. Add Flake Input

Add Serpantinum to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    serpantinum.url = "github:ilyamiro/serpantinum";
  };

  outputs = { self, nixpkgs, serpantinum, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit serpantinum; };
      modules = [
        ./configuration.nix
        serpantinum.nixosModules.default
      ];
    };
  };
}

```

#### 2. configuration.nix

Enable the NixOS module to configure system prerequisites:

```nix
{
  programs.serpantinum.enable = true;
}

```

If you prefer installing the package directly without the system module:

```nix
{ pkgs, serpantinum, ... }:

{
  environment.systemPackages = [
    serpantinum.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}

```

#### 3. Home Manager Configuration

```nix
{ serpantinum, ... }:

{
  imports = [
    serpantinum.homeManagerModules.default
  ];

  programs.serpantinum = {
    enable = true;
    systemd.enable = true;

    settings = {
      wallpaperDir = "/home/username/Pictures/Wallpapers";

      general = {
        language = "en";
        weatherUnit = "metric";
        weatherInterval = 30;
      };

      bar = {
        position = "top";
        style = "solid";
        width = 40;
        workspaceCount = 10;
        modules = {
          left = [ "workspaces" ];
          center = [ "time" ];
          right = [ "tray" [ "kb" "wifi" "bt" "vol" "bat" ] ];
        };
      };

      theme = {
        fontFamily = "Adwaita Mono";
        borderRadius = 12;
        matugen = true;
      };

      notifications = {
        dnd = false;
        position = "top right";
        sound = true;
      };
    };
  };
}

```

#### 4. Updating

Update the flake lockfile and rebuild your system:

```bash
nix flake update serpantinum
sudo nixos-rebuild switch --flake .

```

> **Note:** The automatic installer handles compositor integration on standard distributions. On NixOS / Home Manager, you must manually integrate compositor configs.
> Sample configs, autostart entries, and keybindings for supported window managers and compositors are available in the [compositors](https://github.com/ilyamiro/serpantinum/tree/master/compositors) directory.


#### Required autostart

Remember to add clipboard listeners and required services to your compositor's autostart configuration for the clipboard and the equalizer to work properly.

Example on Hyprland:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("systemctl --user enable --now easyeffects")
end)

```
---

## Running

To run the shell, launch `serpantinumd start`

---

## Credits

* Special thanks to Darkall44/Qylock for providing a gorgeous material SDDM theme!

<br><br><br>

<div align="center">
  <h3>Thanks to all contributors</h3>
  <br>

  <a href="https://github.com/TheRinder2"><img src="https://avatars.githubusercontent.com/u/48689803?v=4&s=48" width="48" height="48" alt="TheRinder2"></a>
  <a href="https://github.com/bizneskind-droid"><img src="https://avatars.githubusercontent.com/u/245046997?v=4&s=48" width="48" height="48" alt="bizneskind-droid"></a>
  <a href="https://github.com/Pigeon78"><img src="https://avatars.githubusercontent.com/u/151051379?v=4&s=48" width="48" height="48" alt="Pigeon78"></a>
  <a href="https://github.com/Eduarduar"><img src="https://avatars.githubusercontent.com/u/104547727?v=4&s=48" width="48" height="48" alt="Eduarduar"></a>
  <a href="https://github.com/Spinty-dev"><img src="https://avatars.githubusercontent.com/u/123001216?v=4&s=48" width="48" height="48" alt="Spinty-dev"></a>
  <a href="https://github.com/MrDexstor"><img src="https://avatars.githubusercontent.com/u/97257847?v=4&s=48" width="48" height="48" alt="MrDexstor"></a>
  <a href="https://github.com/coloramamoe"><img src="https://avatars.githubusercontent.com/u/117035740?v=4&s=48" width="48" height="48" alt="coloramamoe"></a>
  <a href="https://github.com/Zyxilon"><img src="https://avatars.githubusercontent.com/u/234867627?v=4&s=48" width="48" height="48" alt="Zyxilon"></a>
  <a href="https://github.com/gouthamkrishnap"><img src="https://avatars.githubusercontent.com/u/224089015?v=4&s=48" width="48" height="48" alt="gouthamkrishnap"></a>
  <a href="https://github.com/Stoltembergg"><img src="https://avatars.githubusercontent.com/u/312632452?v=4&s=48" width="48" height="48" alt="Stoltembergg"></a>
  <a href="https://github.com/andckadir"><img src="https://avatars.githubusercontent.com/u/175446585?v=4&s=48" width="48" height="48" alt="andckadir"></a>
  <a href="https://github.com/ArseniiTkachuk"><img src="https://avatars.githubusercontent.com/u/257102547?v=4&s=48" width="48" height="48" alt="ArseniiTkachuk"></a>
  <a href="https://github.com/MCUxDaredevil"><img src="https://avatars.githubusercontent.com/u/59441946?v=4&s=48" width="48" height="48" alt="MCUxDaredevil"></a>
  <a href="https://github.com/MILKv2"><img src="https://avatars.githubusercontent.com/u/142674287?v=4&s=48" width="48" height="48" alt="MILKv2"></a>
  <a href="https://github.com/pedrolourencosilva"><img src="https://avatars.githubusercontent.com/u/184855780?v=4&s=48" width="48" height="48" alt="pedrolourencosilva"></a>
  <a href="https://github.com/Vaspyyy"><img src="https://avatars.githubusercontent.com/u/197029450?v=4&s=48" width="48" height="48" alt="Vaspyyy"></a>
  <a href="https://github.com/Sergi122"><img src="https://avatars.githubusercontent.com/u/171693999?v=4&s=48" width="48" height="48" alt="Sergi122"></a>
  <a href="https://github.com/Syrup5845"><img src="https://avatars.githubusercontent.com/u/310795939?v=4&s=48" width="48" height="48" alt="Syrup5845"></a>
  <a href="https://github.com/forteleaf"><img src="https://avatars.githubusercontent.com/u/14119264?v=4&s=48" width="48" height="48" alt="forteleaf"></a>
  <a href="https://github.com/kranks-uga"><img src="https://avatars.githubusercontent.com/u/179175113?v=4&s=48" width="48" height="48" alt="kranks-uga"></a>
  <a href="https://github.com/zynx-real"><img src="https://avatars.githubusercontent.com/u/320626542?v=4&s=48" width="48" height="48" alt="zynx-real"></a>
</div>

<br><br>

---

## License

Copyright (C) 2026 Illia Miroshnichenko

This project is licensed under the GNU Affero General Public License version 3, or (at your option) any later version. See the [LICENSE.md](LICENSE.md) file for the full license text.

