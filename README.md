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
  - **Região** (`⌃⇧2`) — arrasta para selecionar; ajusta a seleção antes de exportar.
  - **Janela** (`⌃⇧3`) — escolhe uma janela (sem sombra).
  - **Ecrã inteiro** (`⌃⇧4`) — captura tudo, com atraso opcional.
- **Conta-gotas** (`⌃⇧1`) — escolhe a cor de qualquer pixel do ecrã com a lupa do
  sistema. Copia logo o **HEX** para o clipboard e mostra um cartão com **RGB** e
  **CSS** a um clique, além de um histórico das **cores recentes** na barra de menus.
- **Editor de anotação** (por defeito) — ao capturar, o ecrã **congela** e podes:
  - **ajustar a seleção** — arrastar as pegas dos cantos/lados ou mover o retângulo;
  - **desenhar por cima** — seta, retângulo, círculo, linha, caneta, marcador e texto,
    com **paleta de cores** e **espessura** à escolha; **anular** com ⌘Z;
  - só depois **Copiar** (⌘C) ou **Guardar** (⌘S). Esc cancela.
  - Desliga em *Definições → "Editar antes de copiar/guardar"* para exportação imediata.
- **Guarda + clipboard** — cada captura pode ir para uma pasta configurável e/ou para o
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
  CaptureEngine.swift      — wrapper de `screencapture` + entrega (CaptureOutput)
  CaptureStore.swift       — histórico de capturas (imagens + thumbnails)
  CapturePreview.swift     — pré-visualização flutuante pós-captura
  Annotation.swift         — modelo de anotação + ShapesCanvas (render partilhado)
  AnnotationToolbar.swift  — barra de ferramentas (tools, cores, espessura, exportar)
  ColorPicker.swift        — conta-gotas do ecrã (NSColorSampler) + toast + histórico
  SelectionOverlay.swift   — overlay de região: congelar + selecionar + anotar
  AnnotationEditorWindow   — editor em janela (modos janela / ecrã inteiro)
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

Com o **editor ligado** (default), a captura de região **congela** o ecrã com
**ScreenCaptureKit** e mostra um overlay onde selecionas/ajustas a área e anotas por cima.
A exportação é **WYSIWYG**: o mesmo `ShapesCanvas` que desenhas no ecrã é recomposto sobre
a imagem congelada via `ImageRenderer` e recortado à seleção — o PNG/JPG sai igual ao que vês.
Janela e ecrã inteiro capturam com `screencapture` e abrem a imagem no editor.

Com o **editor desligado**, o Screenly envolve o binário do sistema `/usr/sbin/screencapture`
(UI de seleção nativa, robusto entre monitores) e exporta logo para pasta + clipboard.

O motor de captura está atrás do protocolo `CaptureEngine` (impl `SystemCapture`), o que
deixa espaço para trocar por outras fontes sem mexer nos chamadores.

## Notes

- Os modos interativos (região/janela) muitas vezes nem precisam da permissão de Gravação de
  Ecrã (a captura é iniciada pelo utilizador via UI do sistema); o ecrã inteiro programático
  precisa — por isso pedimo-la no onboarding.
- Debug: `SCREENLY_DEBUG_WINDOW=settings|gallery|onboarding|editor|overlay` abre a janela no
  arranque; `SCREENLY_DEBUG_EXPORT=/caminho.png` renderiza anotações de exemplo e sai;
  `SCREENLY_DEBUG_VERSION=0.0.1` força uma versão baixa para testar o auto-update.
