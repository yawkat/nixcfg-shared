{ ... }:
{
  # Standby is disabled on every machine, automatically as well as manually.
  # Masking the targets is what makes the "manually" part stick: logind then
  # reports that the machine cannot suspend, so Plasma drops Sleep and
  # Hibernate from its leave screen and `systemctl suspend` fails outright.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Plasma inhibits logind's own handling while a session is running, but the
  # login screen has no session. Without this, closing the lid there would
  # still try to suspend and just fail against the masked target.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };
}
