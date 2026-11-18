# Horror Game

Ein First-Person-Horrorspiel, entwickelt mit **Godot 4.7** (Forward Plus). Du erkundest ein düsteres, verwinkeltes Haus mit Keller, Obergeschoss und Garten, während dich ein Monster und zufällige Schreckmomente in Atem halten.

![Godot](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Status](https://img.shields.io/badge/Status-in_Entwicklung-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Begehbares Haus** mit offenem Erdgeschoss, Obergeschoss, Keller, Dach und Fenstern
- **Außenwelt** mit Nachbarschaft, Kiefern, Gras und Nebel
- **Horror-Director** (Autoload): steuert zufällige Events und Spannungsaufbau
- **Monster-KI** mit Navigation durch das Haus
- **Interaktion & Inventar** auf Basis von COGITO (Türen, Items, Schlüssel, Notizen)
- **Atmosphäre**: dynamische Beleuchtung, Hausgeräusche, PBR-Materialien, glTF-Möbel
- **3D-Startscreen** und **Pausemenü** (ESC) mit Audio-, Kamera- und Grafik-Einstellungen

## Voraussetzungen

- [Godot 4.7](https://godotengine.org/) (Standard-Version, nicht .NET)
- [Git LFS](https://git-lfs.com/) – Modelle, Texturen und Audio (`*.glb`, `*.fbx`, `*.png`, `*.wav`, `*.ogg`) liegen in LFS

## Installation & Start

```bash
git lfs install
git clone <REPO-URL>
cd horror-game
```

1. Godot starten und das Projekt über `project.godot` importieren.
2. Mit **F5** starten (Hauptszene: `scenes/main_menu.tscn`).

## Projektstruktur

| Ordner | Inhalt |
| --- | --- |
| `scenes/` | Level, Haus (`horror_main.tscn`), Monster, Events, Items, Props |
| `scripts/` | Horror-Director, Monster-Logik, Lampen, Hausgeräusche |
| `assets/` | Materialien, Texturen, Modelle, Audio |
| `addons/` | COGITO, Godot State Charts, Input Helper, Quick Audio |
| `tools/` | Editor-Hilfsskripte (z. B. Tür-LOD, Monster-Setup) |
| `docs/` | Dokumentation und Bilder |

## Entwicklung

- Commits nach [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `refactor:`, `chore:` …)
- Neue große Dateitypen zuerst in `.gitattributes` (LFS) eintragen, bevor sie committet werden
- Vor dem Commit prüfen: neue `.uid`-/`.import`-Dateien sind dabei, `.godot/` und Archive nicht

## Credits

- Spielerframework & Interaktionssystem: [COGITO](https://codeberg.org/Phazorknight/Cogito) von Philip Drobar (MIT)
- Weitere Addons: [Godot State Charts](https://github.com/derkork/godot-statecharts), Input Helper, Quick Audio

## Lizenz

Siehe [LICENSE](LICENSE).
