#!/bin/bash
# Cria (uma vez) um certificado self-signed estável para assinar o Screenly.
# Assim a assinatura — e a permissão de Gravação de Ecrã — sobrevive a
# recompilações. Usa uma keychain dedicada com password própria, não a de login.
set -euo pipefail

IDENTITY="Screenly Self Signed"
KEYCHAIN="$HOME/Library/Keychains/screenly-signing.keychain-db"
KPW="screenly-signing"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ Certificado '$IDENTITY' já existe. Nada a fazer."
  exit 0
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "▸ A gerar certificado self-signed (codeSigning)…"
cat > "$WORK/cfg" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = Screenly Self Signed
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cfg" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$IDENTITY" -out "$WORK/id.p12" -passout pass:screenly >/dev/null 2>&1

echo "▸ A criar keychain dedicada…"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KPW" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KPW" "$KEYCHAIN"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P screenly -A -T /usr/bin/codesign >/dev/null 2>&1
security set-key-partition-list -S apple-tool:,apple: -s -k "$KPW" "$KEYCHAIN" >/dev/null 2>&1

# adicionar à lista de pesquisa preservando as existentes
EXISTING=$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')
security list-keychains -d user -s $EXISTING "$KEYCHAIN" >/dev/null 2>&1

echo "✓ Certificado '$IDENTITY' criado."
