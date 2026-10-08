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

This fork builds on the original [Serpantinum](https://github.com/ilyamiro/serpantinum). This comparison is against upstream commit [4ab43a3f023b44f336812bd32d2828ea89118b0a](https://github.com/ilyamiro/serpantinum/commit/4ab43a3f023b44f336812bd32d2828ea89118b0a), not a claim about the latest upstream state.

| Area | Upstream baseline | This fork |
|---|---|---|
| Symbol picker | No unified emoji/glyph/kaomoji picker in this revision. | Adds one picker with emoji, Nerd Font glyph, and kaomoji tabs, search, keyboard navigation, and frequently used items. See the [picker source](src/quickshell/emoji/Emoji.qml). |
| Notifications | Already includes notifications and a Notification Center. | Extends the existing center with text, app, and date filters; grouped history; unread tracking; bulk, per-item, and group dismissal; and timed Do Not Disturb snoozes. See [NotificationCenter.qml](src/quickshell/notifications/NotificationCenter.qml). |
| Fonts | Discovers bundled fonts and files in Serpantinum's user-state directory. | Adds system fonts through Fontconfig alongside fonts in the user-state directory; selected font files are still loaded by the shell. See [ThemeBackend.qml](src/quickshell/singletons/theme/ThemeBackend.qml). |
| Wallpapers | Uses the QML wallpaper surface. | Adds optional `wallpaperBackend = "awww"` for static images. QML remains the default backend and continues to handle video wallpapers. See [Wallpaper.qml](src/quickshell/singletons/theme/Wallpaper.qml). |
| Bar and widgets | Includes workspace indicators and a media widget. | Refines workspace and widget transitions, uses square workspace indicators, and collapses the media widget when there is no active media. |

> [!NOTE]
> The installation instructions below still select the original upstream repository: the Arch command downloads its installer, the Nix flake input is `github:ilyamiro/serpantinum`, and the installer defaults to `ilyamiro/serpantinum`. They do not install this fork.

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

---

## License

Copyright (C) 2026 Illia Miroshnichenko

This project is licensed under the GNU Affero General Public License version 3, or (at your option) any later version. See the [LICENSE.md](LICENSE.md) file for the full license text.

