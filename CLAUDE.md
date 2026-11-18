# Projekt: Godot 4.7.2 Horror-Game

## Git-Workflow
- **Vor jedem Commit:** Mit `git status` prüfen, dass
  - neue `.uid`- und `.import`-Dateien mit im Commit sind,
  - keine `.godot/`-Inhalte und keine Archive (`.zip`, `.rar`) hineingerutscht sind.
- **LFS:** `*.glb`, `*.fbx`, `*.png`, `*.wav`, `*.ogg` laufen über Git LFS (siehe `.gitattributes`). Neue große Dateitypen zuerst in `.gitattributes` eintragen, *bevor* sie committet werden, sonst landen sie dauerhaft in der Historie.
- **Commits:** Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:` ...). Nach jedem fertiggestellten Feature oder Bugfix aktiv einen sauberen Commit vorschlagen.
- **Push:** Erst nach ausdrücklicher Bestätigung pushen. Kein `--force`, `--force-with-lease` oder `--amend` auf bereits gepushten Commits ohne ausdrückliche Anweisung.
- **Branches:** Vor größeren Umbauten oder experimentellen Features (z. B. KI-Verhalten, Refactoring; mehr als ein paar Dateien oder Änderungen an Szenen-Struktur und Autoloads) automatisch einen `feature/<name>`-Branch vorschlagen, statt direkt auf `main` zu arbeiten.
