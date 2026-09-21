"""Build a Breeze Dark variant that only changes the panel background."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

source, output, color, theme_id = sys.argv[1:]
source, output = Path(source), Path(output)
output.mkdir(parents=True)
for name in ("colors", "plasmarc"):
    shutil.copyfile(source / "breeze-dark" / name, output / name)
with (output / "plasmarc").open("a") as stream:
    stream.write("\n[Settings]\nFallbackTheme=breeze-dark\n")
# Including the source and color invalidates Plasma's SVG cache on upgrades.
version = hashlib.sha256((str(source) + color).encode()).hexdigest()[:12]
(output / "metadata.json").write_text(json.dumps({
    "KPlugin": {"Id": theme_id, "Name": "Breeze Dark with machine color",
                "Version": version, "License": "LGPL"},
    "X-Plasma-API": "5.0",
}))

panels = sorted((source / "default").rglob("panel-background.svgz"))
if not panels:
    raise RuntimeError("Breeze panel assets were not found")
for panel in panels:
    svg = ET.fromstring(gzip.decompress(panel.read_bytes()))
    changed = 0
    for element in svg.iter():
        classes = element.get("class", "").split()
        if "ColorScheme-Background" not in classes:
            continue
        # Remove theme recoloring from just the panel background shapes;
        # keep the upstream geometry, opacity, shadows and other color roles.
        classes.remove("ColorScheme-Background")
        element.set("class", " ".join(classes))
        style = element.get("style", "")
        style = re.sub(r"(?i)currentcolor", color, style)
        element.set("style", style.rstrip(";") + ";color:" + color)
        for name in ("fill", "stroke", "stop-color"):
            if element.get(name, "").lower() == "currentcolor":
                element.set(name, color)
        changed += 1
    if not changed:
        raise RuntimeError(f"Breeze panel has no recognizable background: {panel}")
    target = output / panel.relative_to(source / "default")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(gzip.compress(ET.tostring(svg, encoding="utf-8", xml_declaration=True), mtime=0))
