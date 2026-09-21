#!/usr/bin/env bash
# Installs the packages this setup needs (Arch/pacman), then symlinks
# this repo's config folders into ~/.config so labwc and quickshell
# pick them up. Existing real files/dirs are backed up with a
# .bak-<timestamp> suffix before being replaced.
#
#   ./install.sh            install packages (repo + AUR) + link configs
#   ./install.sh --no-pkgs  skip the package/service step
#
# Assumes a booted Arch base system (bootloader, network, user account)
# and a tty login; start the session with `labwc` from the console.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

PACKAGES=(
    labwc                    # compositor
    quickshell               # bar + wallpaper (quickshell/)
    kitty                    # terminal (Ctrl+Alt+T)
    zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions  # shell (zsh/)
    fzf                      # fuzzy finder (Ctrl+R / Ctrl+T / Alt+C in zsh)
    fastfetch                # system info banner (fastfetch/)
    wofi                     # launcher (Super) + clipboard picker
    cliphist wl-clipboard    # clipboard history (Super+V)
    grim slurp               # screenshot to clipboard (Print = region, Shift+Print = full)
    papirus-icon-theme       # icon theme (Papirus-Dark: bar, labwc, GTK) — see gtk-*/settings.ini, labwc/environment
    adwaita-icon-theme       # fallback for icons Papirus lacks
    gsettings-desktop-schemas xdg-desktop-portal xdg-desktop-portal-gtk  # dark mode for GTK/portal apps
    xdg-desktop-portal-wlr   # screen sharing (labwc ships labwc-portals.conf selecting it)
    noto-fonts noto-fonts-cjk  # Cyrillic / CJK coverage
    pipewire pipewire-pulse pipewire-alsa wireplumber  # audio
    pavucontrol              # volume mixer (sits in the tray)
    firefox                  # browser
    base-devel git           # needed to build yay from the AUR
)

# Installed with yay after it has been bootstrapped.
AUR_PACKAGES=(
    claude-desktop           # Claude desktop app
    claude-code              # Claude Code CLI
    proton-mail              # Proton Mail desktop app (tray)
    vesktop                  # Discord client
    fzf-tab-git              # Tab completion through fzf (zsh/)
)

install_packages() {
    if ! command -v pacman >/dev/null 2>&1; then
        echo "pacman not found; skipping package install (this script targets Arch)." >&2
        return
    fi
    local missing=()
    for p in "${PACKAGES[@]}"; do
        pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        echo "all packages already installed"
        return
    fi
    echo "installing: ${missing[*]}"
    sudo pacman -S --needed "${missing[@]}"
}

# yay is not in the official repos; bootstrap it from the AUR once.
install_yay() {
    if command -v yay >/dev/null 2>&1; then
        echo "yay already installed"
        return
    fi
    if ! command -v pacman >/dev/null 2>&1; then
        return
    fi
    local build_dir
    build_dir="$(mktemp -d)"
    echo "building yay from the AUR in $build_dir"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
    (cd "$build_dir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
}

install_aur_packages() {
    if ! command -v yay >/dev/null 2>&1; then
        echo "yay not available; skipping AUR packages: ${AUR_PACKAGES[*]}" >&2
        return
    fi
    local missing=()
    for p in "${AUR_PACKAGES[@]}"; do
        pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        echo "all AUR packages already installed"
        return
    fi
    echo "installing from AUR: ${missing[*]}"
    yay -S --needed "${missing[@]}"
}

# PipeWire runs as user services; make sure they are enabled and up so
# audio (and the pavucontrol tray icon) work in the first session.
enable_audio() {
    command -v systemctl >/dev/null 2>&1 || return
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null \
        && echo "enabled pipewire user services" \
        || echo "could not enable pipewire user services (no user session bus?)" >&2
}

# Make zsh the login shell. Takes effect on the next login; kitty windows
# opened in the current session keep inheriting $SHELL from the tty login.
set_login_shell() {
    command -v zsh >/dev/null 2>&1 || return
    local zsh_path current
    zsh_path="$(command -v zsh)"
    current="$(getent passwd "$USER" | cut -d: -f7)"
    if [ "$current" = "$zsh_path" ]; then
        echo "login shell already zsh"
        return
    fi
    echo "changing login shell to $zsh_path (chsh will ask for your password)"
    chsh -s "$zsh_path"
}

if [ "${1:-}" != "--no-pkgs" ]; then
    install_packages
    install_yay
    install_aur_packages
    enable_audio
    set_login_shell
fi

link() {
    local src="$SCRIPT_DIR/$1"
    local dest="$2"

    if [ -L "$dest" ]; then
        if [ "$(readlink "$dest")" = "$src" ]; then
            echo "up to date: $dest"
            return
        fi
        rm "$dest"
    elif [ -e "$dest" ]; then
        echo "backing up existing $dest -> $dest.bak-$TIMESTAMP"
        mv "$dest" "$dest.bak-$TIMESTAMP"
    fi

    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "linked: $dest -> $src"
}

link labwc "$CONFIG_HOME/labwc"
link quickshell "$CONFIG_HOME/quickshell"
link gtk-3.0 "$CONFIG_HOME/gtk-3.0"
link gtk-4.0 "$CONFIG_HOME/gtk-4.0"
link wofi "$CONFIG_HOME/wofi"
link kitty "$CONFIG_HOME/kitty"
link zsh/zshrc "$HOME/.zshrc"
link fastfetch "$CONFIG_HOME/fastfetch"
link xdg-desktop-portal-wlr "$CONFIG_HOME/xdg-desktop-portal-wlr"
link fontconfig/conf.d/49-th-sarabun.conf "$CONFIG_HOME/fontconfig/conf.d/49-th-sarabun.conf"
link fonts/CommitMonoNerdFontMono "$HOME/.local/share/fonts/CommitMonoNerdFontMono"
link fonts/THSarabunNew "$HOME/.local/share/fonts/THSarabunNew"

if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f "$HOME/.local/share/fonts/CommitMonoNerdFontMono" "$HOME/.local/share/fonts/THSarabunNew" >/dev/null
    echo "refreshed font cache"
fi

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    echo "set GTK color-scheme to prefer-dark, icon theme to Papirus-Dark"
fi

if command -v labwc >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    labwc -r
    echo "reloaded labwc config"
fi

echo "done. the bar starts with labwc via labwc/autostart; run 'qs' to start it now."
