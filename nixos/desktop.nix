{
  config,
  pkgs,
  ...
}:
{
  services.xserver.xkb = {
    layout = "de";
    variant = "nodeadkeys";
  };

  # KDE Connect opens firewall ports for phone pairing, so keep it off work
  # machines to match the personal-only gating used elsewhere.
  programs.kdeconnect.enable = !config.host.work;

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];
}
