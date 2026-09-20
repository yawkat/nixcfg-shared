{ config, lib, ... }:
let
  inherit (config.host) idle;

  locks = idle.lockAfter != null;

  # powerdevil keeps one profile per power source. All three get the same
  # behaviour: a machine should not idle out differently just because it
  # happens to be running on battery.
  profile = {
    # With standby gone the power button is the only way to shut down from the
    # keyboard, so it must not fall back to suspending.
    powerButtonAction = "shutDown";
    autoSuspend.action = "nothing";

    # KDE's default lid action is sleep, which the masked sleep target would
    # only fail at. Closing the lid does whatever the idle timeout would
    # eventually have done.
    whenLaptopLidClosed = if locks then "lockScreen" else "turnOffScreen";

    dimDisplay =
      if idle.dimAfter == null then { enable = false; } else { idleTimeout = idle.dimAfter; };

    turnOffDisplay.idleTimeout = if idle.screenOffAfter == null then "never" else idle.screenOffAfter;
  };
in
{
  assertions = [
    {
      assertion = !locks || lib.mod idle.lockAfter 60 == 0;
      message = "host.idle.lockAfter is stored as whole minutes, so it must be a multiple of 60.";
    }
  ];

  programs.plasma = {
    enable = true;

    powerdevil = {
      AC = profile;
      battery = profile;
      lowBattery = profile;
      # Left alone this suspends on a critical battery, which is exactly the
      # standby the rest of this module takes away.
      batteryLevels.criticalAction = "shutDown";
    };

    kscreenlocker = {
      autoLock = locks;
      timeout = if locks then idle.lockAfter / 60 else null;
    };
  };
}
