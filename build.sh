#!/bin/bash
# Compila, assina (com identidade estável) e instala o Screenly em /Applications.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Screenly Self Signed"
KEYCHAIN="$HOME/Library/Keychains/screenly-signing.keychain-db"

# Garante o certificado estável — sem ele a assinatura mudaria a cada build e a
# permissão de Gravação de Ecrã teria de ser reconcedida.
if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "▸ Certificado em falta — a criar…"
  ./setup-signing.sh
fi

echo "▸ A compilar (release)…"
swift build -c release

APP="Screenly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Screenly" "$APP/Contents/MacOS/Screenly"
cp "Info.plist" "$APP/Contents/Info.plist"
[ -f "Screenly.icns" ] && cp "Screenly.icns" "$APP/Contents/Resources/Screenly.icns"

sign() {
  security unlock-keychain -p "screenly-signing" "$KEYCHAIN" 2>/dev/null || true
  codesign --force --deep --sign "$IDENTITY" --keychain "$KEYCHAIN" "$1"
}

echo "▸ A assinar com '$IDENTITY'…"
sign "$APP"

# Instalar em /Applications e reiniciar
DEST="/Applications/Screenly.app"
pkill -f "Screenly.app/Contents/MacOS/Screenly" 2>/dev/null || true
sleep 1
if rm -rf "$DEST" 2>/dev/null && cp -R "$APP" "$DEST" 2>/dev/null; then
  sign "$DEST"
  open "$DEST"
  echo "✓ Instalado, assinado e reiniciado: $DEST"
else
  echo "✓ Pronto: $APP  (copia para /Applications manualmente)"
  DEST="$APP"
fi

echo "  Requisito:"
codesign -d --requirements - "$DEST" 2>&1 | grep -i designated | sed 's/^/    /'
