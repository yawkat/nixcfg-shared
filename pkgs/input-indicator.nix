{
  lib,
  stdenvNoCC,
  python3,
  dbus,
}:
let
  python = python3.withPackages (ps: [
    ps.dbus-next
    ps.pyudev
    ps.pillow
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "input-indicator";
  version = "1.0";
  src = ./input-indicator;
  nativeBuildInputs = [ python ];
  nativeCheckInputs = [ dbus ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf -- ${python}/bin/python -m unittest discover -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 indicator.py $out/lib/input-indicator/indicator.py
    mkdir -p $out/bin
    cat > $out/bin/input-indicator <<SCRIPT
    #!${python}/bin/python
    import runpy
    runpy.run_path("$out/lib/input-indicator/indicator.py", run_name="__main__")
    SCRIPT
    chmod +x $out/bin/input-indicator
    runHook postInstall
  '';
  meta = {
    description = "USB keyboard and mouse connection indicator for the Plasma tray";
    mainProgram = "input-indicator";
    platforms = lib.platforms.linux;
  };
}
