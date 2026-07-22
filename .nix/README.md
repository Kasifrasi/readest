# Readest unter NixOS

Vom Repository-Root aus die Entwicklungsumgebung öffnen:

```bash
nix develop ./.nix
```

Beim ersten Mal das Repository einrichten und danach Tauri starten:

```bash
setup-readest
dev
```

`dev` startet `pnpm tauri dev` mit dem Rust-Toolchain und den von Tauri v2
benötigten GTK-/WebKitGTK-Bibliotheken aus der Flake.
