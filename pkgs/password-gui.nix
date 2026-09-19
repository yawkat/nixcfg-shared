{
  lib,
  maven,
  fetchFromGitHub,
  makeWrapper,
  writeText,
  jdk21,
  qt6,
}:
let
  desktopItem = writeText "at.yawk.password.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Passwords
    Comment=Password manager
    Exec=password-gui
    Icon=dialog-password
    Terminal=false
    Categories=Utility;Security;Qt;
  '';

  # QtJambi requires the system Qt to match its own minor version exactly, so
  # pin the Maven property to whatever Qt nixpkgs ships instead of the value
  # hardcoded upstream.
  qtVersion = qt6.qtbase.version;

  qtModules = [
    qt6.qtbase
    qt6.qtwayland
    qt6.qtsvg
  ];
  qtLibPath = lib.makeLibraryPath qtModules;
  qtPluginPath = lib.concatMapStringsSep ":" (p: "${p}/${qt6.qtbase.qtPluginPrefix}") qtModules;
in
maven.buildMavenPackage {
  pname = "password-gui";
  version = "1.0-unstable-2026-09-19";

  src = fetchFromGitHub {
    owner = "yawkat";
    repo = "password-java";
    # PR #1 (gui) head, launcher/desktop dropped.
    rev = "e134179aa81a71a34320a613af08d7b0c74d8d59";
    hash = "sha256-Ms+mMkmlizUAQtyzx1SHgdTLupcrrJtBlPcXq8Ae+6s=";
  };

  # Build the GUI and its dependencies. Use -DskipTests rather than
  # maven.test.skip so the client test-jar (a test-scoped dependency of gui) is
  # still packaged and resolves; the GUI tests need a display to *run*, so they
  # are compiled but not executed.
  mvnParameters = "-pl gui -am -DskipTests -Dqtjambi.version=${qtVersion}";
  mvnHash = "sha256-lFP7AX1hM5yAyI2Ru1AEDL+hJuDaP+y/pwhrFH1S5LA=";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm644 gui/target/gui-1.0-SNAPSHOT-shaded.jar "$out/share/password-gui/password-gui.jar"

    makeWrapper ${jdk21}/bin/java "$out/bin/password-gui" \
      --add-flags "--enable-native-access=ALL-UNNAMED -Djava.library.path=${qtLibPath} -jar $out/share/password-gui/password-gui.jar" \
      --set-default QT_QPA_PLATFORM "wayland;xcb" \
      --prefix QT_PLUGIN_PATH : "${qtPluginPath}" \
      --prefix LD_LIBRARY_PATH : "${qtLibPath}"

    install -Dm644 ${desktopItem} "$out/share/applications/at.yawk.password.desktop"

    runHook postInstall
  '';

  meta = {
    description = "Qt desktop GUI for the yawkat password manager";
    homepage = "https://github.com/yawkat/password-java";
    mainProgram = "password-gui";
    # The upstream pom only depends on qtjambi-native-linux-x64.
    platforms = [ "x86_64-linux" ];
  };
}
