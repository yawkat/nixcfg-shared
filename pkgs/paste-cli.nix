{
  lib,
  maven,
  fetchFromGitHub,
  makeWrapper,
  writeText,
  jdk21,
  wl-clipboard,
  libnotify,
  xdg-utils,
}:
let
  # Appears in Spectacle's Export -> "Open With" (and any image "Open With"),
  # so screenshots annotated in Spectacle can be uploaded straight from there.
  spectacleDesktop = writeText "at.yawk.paste.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=s.yawk.at
    Comment=Upload to the paste server
    Icon=document-share
    Exec=paste-cli file %f
    MimeType=image/png;image/jpeg;
    Terminal=false
    NoDisplay=true
  '';

  # Dolphin right-click "Share via s.yawk.at" for any file.
  serviceMenu = writeText "at.yawk.paste-servicemenu.desktop" ''
    [Desktop Entry]
    Type=Service
    X-KDE-ServiceTypes=KonqPopupMenu/Plugin
    X-KDE-Priority=TopLevel
    MimeType=all/allfiles;
    Actions=pasteUpload;

    [Desktop Action pasteUpload]
    Name=Share via s.yawk.at
    Icon=document-share
    Exec=paste-cli file %f
  '';
in
maven.buildMavenPackage {
  pname = "paste-cli";
  version = "1.0-unstable-2026-09-19";

  src = fetchFromGitHub {
    owner = "yawkat";
    repo = "paste";
    # PR #2 (cli-stdin-spectacle) head, launcher/desktop dropped.
    rev = "29bfe554ef6ce6483fcbbea8ec34c36d729b3d82";
    hash = "sha256-bYWEi3gnuk9R4kaJUrfyXfN59u5HOAF1osx38GmaVvg=";
  };

  # Build only the CLI and its dependencies (shared, client); skip the server.
  mvnParameters = "-pl cli -am -Dmaven.test.skip=true";
  mvnHash = "sha256-/nPyQbrA06HtmS6GNPpv2wuGlH8+C+u0uiHPjbGEl+o=";

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm644 cli/target/cli-1.0-SNAPSHOT-shaded.jar "$out/share/paste/paste.jar"

    # Installed as paste-cli, not paste, to avoid shadowing coreutils' paste.
    makeWrapper ${jdk21}/bin/java "$out/bin/paste-cli" \
      --add-flags "-Djava.awt.headless=true -jar $out/share/paste/paste.jar" \
      --prefix PATH : ${
        lib.makeBinPath [
          wl-clipboard
          libnotify
          xdg-utils
        ]
      }

    install -Dm644 ${spectacleDesktop} "$out/share/applications/at.yawk.paste.desktop"
    install -Dm644 ${serviceMenu} "$out/share/kio/servicemenus/at.yawk.paste.desktop"

    runHook postInstall
  '';

  meta = {
    description = "CLI that uploads stdin, files and screenshots to a paste server";
    homepage = "https://github.com/yawkat/paste";
    mainProgram = "paste-cli";
    platforms = lib.platforms.linux;
  };
}
