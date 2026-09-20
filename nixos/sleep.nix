{ ... }:
{
  # Standby is disabled on every machine, automatically as well as manually.
  #
  # sleep.conf is what does the real work: logind checks SleepConfig.allow
  # before anything else, so with these off CanSuspend and friends answer "no"
  # and Plasma greys out Sleep and Hibernate instead of offering an action that
  # cannot work. Masking alone would not achieve this — logind decides whether
  # sleep is supported from /sys/power and sleep.conf, never from whether the
  # unit happens to be masked.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  # Belt and braces for anything that goes straight to the units rather than
  # asking logind. suspend-then-hibernate is included because its target does
  # not depend on sleep.target directly, only its service does.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
    suspend-then-hibernate.enable = false;
  };

  # Plasma inhibits logind's own handling while a session is running, but the
  # login screen has no session. Without this, closing the lid there would
  # still try to suspend.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };
}
