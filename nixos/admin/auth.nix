{ ... }:
# yawkat-admin may share its password with yawkat, and yawkat's session runs
# untrusted code that can learn it (it is typed there, into the password
# manager for one). So knowing the password must not be enough from inside
# that session: yawkat-admin (and root) only authenticate where someone is at
# the keyboard, at a text console or a display manager login. The ways a yawkat
# process could otherwise use it:
# - su: only for wheel, which yawkat isn't
# - polkit (pkexec, run0, machinectl shell, KDE's "requires admin" dialogs):
#   a yawkat process is never offered an admin to authenticate as. polkit falls
#   back to root when a rule names nobody valid, so it names nobody, who has no
#   password and can't authenticate. Actions a group is granted outright (such
#   as NetworkManager's for the networkmanager group) don't ask for an admin.
# sudo has no rule for yawkat. A host that runs sshd has to keep it from
# taking passwords.
{
  security.pam.services.su.requireWheel = true;

  # Not security.polkit.extraConfig: that goes after NixOS's own admin rule
  # (unix-group:wheel) in 10-nixos.rules, and the first admin rule that answers
  # wins. Files are read in order of their names.
  environment.etc."polkit-1/rules.d/00-admin-console-only.rules".text = ''
    polkit.addAdminRule(function(action, subject) {
      if (subject.user == "yawkat") {
        return ["unix-user:nobody"];
      }
    });
  '';
}
