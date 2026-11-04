# The helper behind password-gui's virtual security key (password-java's
# services.password-uhid, imported in flake.nix), so browsers can use the
# passkeys in the password database. The app turns it on with
# `securityKey=true` in ~/.config/password-gui/config.properties.
#
# yawkat must not get /dev/uhid itself: whoever opens it chooses what the
# device is, so a yawkat process could create a keyboard and type into
# yawkat-admin's session or at a text console login, past what admin/auth.nix
# relies on. The helper only ever creates the one security key.
#
# What the group still allows: a yawkat process can plug in a security key
# while yawkat-admin is at the seat, and a browser there takes the first key
# that answers a passkey registration, which could give yawkat a way into that
# account. Accepted because passkeys are registered from yawkat's session, not
# yawkat-admin's.
{
  services.password-uhid.enable = true;
  users.users.yawkat.extraGroups = [ "password-uhid" ];
}
