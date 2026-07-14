# Screenly 📸

Screenshots rápidos na barra de menus do Mac. Atalhos globais para capturar
**região**, **janela** ou **ecrã inteiro** — guarda numa pasta, copia para o
clipboard e mostra as capturas recentes. Feito por nós, sem anúncios nem lixo.

## ⬇️ Install

**[⬇️ Descarregar Screenly (.dmg)](https://github.com/itsjustiago/Screenly/releases/latest/download/Screenly.dmg)**

1. Abre o **Screenly.dmg** descarregado e arrasta o **Screenly.app** para **Applications**.
2. **Primeiro arranque** — uma vez só, porque não vem de uma conta paga de developer Apple:
   - Faz duplo-clique no Screenly. O macOS diz que *"não foi possível verificar"* → clica **Concluído**.
   - Abre **Definições do Sistema → Privacidade e Segurança**, desce até **Segurança** e
     clica **Abrir Mesmo Assim** na linha do Screenly. Confirma com Touch ID / password.
   - O Screenly abre — e nunca mais pergunta nesse Mac.
3. No onboarding, concede a permissão de **Gravação de Ecrã** (necessária para capturar).
   Podes ativá-la depois em **Privacidade e Segurança → Gravação de Ecrã**.

## Features

- **Três modos de captura**, cada um com o seu atalho global:
  - **Região** (`⌃⇧2`) — arrasta para selecionar; Espaço alterna para modo janela.
  - **Janela** (`⌃⇧3`) — escolhe uma janela (sem sombra).
  - **Ecrã inteiro** (`⌃⇧4`) — captura tudo, com atraso opcional.
- **Guarda + clipboard** — cada captura vai para uma pasta configurável **e** para o
  clipboard, pronta a colar.
- **Pré-visualização flutuante** ao capturar — clica para revelar no Finder.
- **Histórico de recentes** na barra de menus + uma **galeria pesquisável** com todas as
  capturas (copiar, revelar, fixar, apagar).
- **Atalhos, pasta, formato (PNG/JPG) e mais** configuráveis nas Definições.
- **Iniciar no login** e **update com um clique**.
- Sem ícone na Dock.

## Updates

O Screenly verifica o GitHub por uma release mais recente no arranque (toggle nas
Definições). Quando há uma disponível, a barra de menus mostra **⤓ Atualizar…**.
Clica e o Screenly **descarrega, instala e reinicia-se** — sem arrastar, sem Terminal.

## O aviso "unidentified developer"

O Screenly é assinado com um certificado self-signed e não está notarizado pela Apple
(isso exige uma conta paga de developer). Por isso o **primeiro** arranque precisa de
**Abrir Mesmo Assim** nas Definições; depois disso abre normalmente. Não há nada de errado.

A assinatura é feita com uma **identidade estável** (não ad-hoc), para que a permissão de
Gravação de Ecrã **cole entre recompilações** em vez de ser pedida a cada build.

## Build from source

```bash
./build.sh    # compila, assina, instala em /Applications e relança
```

O primeiro run cria um certificado self-signed (`./setup-signing.sh`) numa keychain
dedicada. Dá à app uma **identidade estável** entre recompilações.

Requisitos: macOS 14+ e as Command Line Tools (`swift`).

- Regenerar o ícone: `swift make-icon.swift && iconutil -c icns Screenly.iconset -o Screenly.icns`
- Empacotar o DMG: `./make-dmg.sh`

### Releasing a new version

1. Bump `CFBundleShortVersionString` (e `CFBundleVersion`) no `Info.plist`.
2. `./build.sh && ./make-dmg.sh`
3. `gh release create vX.Y.Z Screenly.dmg Screenly.zip --title "Screenly X.Y.Z" --notes "…"`

Os dois assets importam: **Screenly.dmg** para quem instala de novo,
**Screenly.zip** para o auto-updater das cópias já instaladas.

## Project layout

```
Sources/Screenly/
  main.swift              — entry point (menu-bar app)
  AppDelegate.swift        — NSStatusItem, popover, hotkeys, lifecycle
  CaptureMode.swift        — modos de captura + atalhos por modo
  CaptureEngine.swift      — wrapper de `screencapture` (guardar + clipboard + preview)
  CaptureStore.swift       — histórico de capturas (imagens + thumbnails)
  CapturePreview.swift     — pré-visualização flutuante pós-captura
  Permissions.swift        — permissão de Gravação de Ecrã
  MenuPanel.swift          — painel da barra de menus
  GalleryPanel.swift       — galeria pesquisável de todas as capturas
  SettingsWindow.swift     — definições
  Onboarding.swift         — janela de boas-vindas
  DesignKit.swift          — linguagem visual partilhada (Brand teal)
  HotKey.swift / Shortcut  — atalhos globais (Carbon)
  Updater.swift            — check de release via GitHub API
  UpdateController.swift   — download + swap + relaunch automático
```

## Como funciona a captura

O Screenly envolve o binário do sistema `/usr/sbin/screencapture`, o que dá a UI de
seleção nativa (crosshair, Espaço para modo janela) de borla e é robusto entre monitores.
Cada captura é lida do ficheiro, guardada na pasta escolhida + no histórico interno, e
copiada para o clipboard. O motor está atrás de um protocolo (`CaptureEngine`), por isso
pode passar mais tarde para **ScreenCaptureKit** (anotação, captura programática) sem mexer
no resto da app.

## Notes

- Os modos interativos (região/janela) muitas vezes nem precisam da permissão de Gravação de
  Ecrã (a captura é iniciada pelo utilizador via UI do sistema); o ecrã inteiro programático
  precisa — por isso pedimo-la no onboarding.
- Debug: `SCREENLY_DEBUG_WINDOW=settings|gallery|onboarding` abre a janela no arranque;
  `SCREENLY_DEBUG_VERSION=0.0.1` força uma versão baixa para testar o auto-update.
