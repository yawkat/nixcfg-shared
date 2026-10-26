# auth.nix with users.nix: yawkat can't su, and polkit offers it no admin to
# authenticate as, while yawkat-admin keeps both. Where NetworkManager runs,
# yawkat may still change network settings.
#
# Run with: nix build .#checks.x86_64-linux.admin-auth
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "admin-auth";
  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        ./auth.nix
        ../users.nix
      ];
      security.polkit.enable = true;
      networking.networkmanager.enable = true;
      users.users.yawkat.password = "pw";
      users.users.yawkat-admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        password = "pw";
      };
      environment.systemPackages = [ (pkgs.python3.withPackages (p: [ p.pexpect ])) ];
      environment.etc."check-auth.py".source = ./check-auth.py;
    };
  testScript = ''
    machine.wait_for_unit("multi-user.target")

    def check(user, *args):
        command = "python3 /etc/check-auth.py " + " ".join(args)
        out = machine.succeed(f"su - {user} -c '{command}'")
        print(out)
        return out

    with subtest("yawkat isn't in wheel, but in networkmanager"):
        groups = machine.succeed("id -Gn yawkat").split()
        assert "wheel" not in groups, groups
        assert "networkmanager" in groups, groups

    with subtest("yawkat can't su, even with the password"):
        assert "status: 0" not in check("yawkat", "su", "yawkat-admin")
        assert "status: 0" not in check("yawkat", "su", "root")

    with subtest("polkit offers yawkat no admin to authenticate as"):
        out = check("yawkat", "pkexec")
        assert "authenticating-as: Unprivileged" in out, out  # nobody, by its real name
        assert "status: 0" not in out, out

    with subtest("but yawkat may change NetworkManager's system settings"):
        pkcheck = "pkcheck --action-id org.freedesktop.NetworkManager.settings.modify.system --process $$"
        machine.succeed(f"su - yawkat -c '{pkcheck}'")
        # by its group: without it, it takes an admin's password
        machine.fail(f"su - yawkat-admin -c '{pkcheck}'")

    with subtest("yawkat-admin still can"):
        assert "status: 0" in check("yawkat-admin", "su", "yawkat")
        out = check("yawkat-admin", "pkexec")
        assert "authenticating-as: yawkat-admin" in out, out
        # Whether it then succeeds can't be tested here: su - from the test driver makes no logind session, and
        # polkit's helper fails with "No session for cookie" before it looks at the password
  '';
}
