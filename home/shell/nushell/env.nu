# Nushell Environment Config File
# This file is loaded before config.nu

# Source the nix-darwin environment on macOS
# This ensures GUI-launched terminals get the correct Nix paths
if (sys host | get name) == "Darwin" {
    if ("/nix/var/nix/profiles/default" | path exists) {
        # Set up Nix paths - this matches what /etc/zshenv does
        let nix_paths = [
            $"($env.HOME)/.nix-profile/bin"
            $"/etc/profiles/per-user/($env.USER)/bin"
            "/run/current-system/sw/bin"
            "/nix/var/nix/profiles/default/bin"
        ]

        # Get current PATH and filter out any existing nix paths to avoid duplicates
        let current_path = ($env.PATH | split row (char esep))
        let filtered_path = ($current_path | where {|p| not ($nix_paths | any {|np| $p == $np})})

        # Prepend nix paths to the filtered PATH
        $env.PATH = ($nix_paths | append $filtered_path | str join (char esep))

        # Set other Nix environment variables
        $env.NIX_PATH = $"nixpkgs=flake:nixpkgs:/nix/var/nix/profiles/per-user/root/channels"
        $env.NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt"
        $env.NIX_USER_PROFILE_DIR = $"/nix/var/nix/profiles/per-user/($env.USER)"
        $env.NIX_PROFILES = "/nix/var/nix/profiles/default /run/current-system/sw /etc/profiles/per-user/$USER $HOME/.nix-profile"

        # Set XDG paths
        let xdg_config_base = [
            $"($env.HOME)/.nix-profile/etc/xdg"
            $"/etc/profiles/per-user/($env.USER)/etc/xdg"
            "/run/current-system/sw/etc/xdg"
            "/nix/var/nix/profiles/default/etc/xdg"
        ]
        $env.XDG_CONFIG_DIRS = ($xdg_config_base | str join ":")

        let xdg_data_base = [
            $"($env.HOME)/.nix-profile/share"
            $"/etc/profiles/per-user/($env.USER)/share"
            "/run/current-system/sw/share"
            "/nix/var/nix/profiles/default/share"
        ]
        $env.XDG_DATA_DIRS = ($xdg_data_base | str join ":")

        # TERMINFO paths
        let terminfo_dirs = [
            $"($env.HOME)/.nix-profile/share/terminfo"
            $"/etc/profiles/per-user/($env.USER)/share/terminfo"
            "/run/current-system/sw/share/terminfo"
            "/nix/var/nix/profiles/default/share/terminfo"
            "/usr/share/terminfo"
        ]
        $env.TERMINFO_DIRS = ($terminfo_dirs | str join ":")
    }
}
