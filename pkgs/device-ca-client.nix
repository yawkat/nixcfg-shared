{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication {
  pname = "cert-request";
  version = "0-unstable";

  src = fetchFromGitHub {
    owner = "yawkat";
    repo = "device-ca";
    rev = "b3503488320111493b91dc80f6c92296d1b69cde";
    hash = "sha256-ZN2CAfDMyES4ZdZf2784V2pf0Z7TEARWRi9iAguOhdE=";
  };

  format = "other"; # not a standard Python package, just a script

  propagatedBuildInputs = with python3Packages; [
    cryptography
    requests
  ];

  installPhase = ''
    install -Dm755 $src/cert-request.py $out/bin/cert-request
  '';

  meta = {
    description = "Client for yawk.at local PKI";
    mainProgram = "cert-request";
  };
}
