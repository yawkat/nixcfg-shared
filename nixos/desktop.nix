{ pkgs, ... }:
{
  services.xserver.xkb = {
    layout = "de";
    variant = "nodeadkeys";
  };

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # Boot is already gated by the LUKS passphrase, so skip the SDDM login
  # prompt on the first session after boot. Locking the session still
  # requires the account password.
  services.displayManager.autoLogin = {
    enable = true;
    user = "yawkat";
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
