#!/bin/bash
# Empacota a app: Screenly.dmg (instalação a arrastar) + Screenly.zip (auto-update).
set -euo pipefail
cd "$(dirname "$0")"

[ -d "Screenly.app" ] || { echo "Screenly.app não existe — corre ./build.sh primeiro."; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "Screenly.app" "$STAGING/Screenly.app"
ln -s /Applications "$STAGING/Applications"

rm -f Screenly.dmg
hdiutil create -volname "Screenly" -srcfolder "$STAGING" -ov -format UDZO -quiet Screenly.dmg

# Zip usado pelo atualizador embutido (ditto preserva o bundle + assinatura).
rm -f Screenly.zip
ditto -c -k --keepParent "Screenly.app" Screenly.zip

echo "✓ Screenly.dmg + Screenly.zip criados"
