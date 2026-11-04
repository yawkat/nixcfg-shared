# The helper behind password-gui's virtual security key (password-java's
# services.password-uhid, imported in flake.nix), so browsers can use the
# passkeys in the password database. The app turns it on with
# `securityKey=true` in ~/.config/password-gui/config.properties.
#
# yawkat must not get /dev/uhid itself: whoever opens it chooses what the
# device is, so a yawkat process could create a keyboard and type into
# yawkat-admin's session or at a text console login, past what admin/auth.nix
# relies on. The helper only ever creates FIDO security keys.
#
# What the group still allows: any yawkat process, not just password-gui, can
# plug in a security key that it fully controls, and keep it plugged in while
# yawkat-admin is at the seat. So yawkat-admin's session must not use FIDO
# keys at all: the fake key can answer first in a browser's passkey
# registration or in `ssh-keygen -t ed25519-sk`, and keep the credential; it
# learns a hash of the PIN typed for it, which is easy to brute-force; and it
# can break every sign-in with a key. Nothing there uses one today. If that
# changes, this has to be revisited first.
{
  services.password-uhid.enable = true;
  users.users.yawkat.extraGroups = [ "password-uhid" ];
}
