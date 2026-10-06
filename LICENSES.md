# Licensing and redistribution inventory

## Project source code

The root [LICENSE](LICENSE) applies the MIT License to the independently implemented Godot photo booth application source and project-authored documentation/build scripts. Copyright holder is listed in that file. It does not relicense third-party software or the museum media/branding below.

The Godot codebase was written from functional requirements; Unity application source files were not ported.

## Bundled third-party software

- **Godot Engine 4.7.2:** MIT. `licenses/Godot-MIT.txt` contains its MIT notice. Godot's 102 component copyright records and 19 license texts are generated from this exact engine build into `licenses/Godot-Third-Party.txt` each time `Build-Windows.ps1` runs. This includes compatible non-MIT notices such as BSD, Apache, OFL, MPL, Zlib, and others.
- **cloudflared 2026.3.0:** Apache License 2.0. The executable is included in the runtime package; the license text is in `licenses/Apache-2.0.txt`. The upstream repository does not list a separate root NOTICE file. Upstream: <https://github.com/cloudflare/cloudflared>.
- **Noto Sans KR:** SIL Open Font License 1.1. The font is unchanged; its copyright and full OFL notice are in `assets/fonts/NotoSansKR-OFL.txt` and are copied to the package.
- **CameraBridge:** Uses only Windows/.NET Framework inbox APIs (Windows Forms and System.Drawing); no external NuGet package is referenced or bundled.

## Included museum media and branding

The Godot asset audit found 19 background/result images byte-for-byte identical (SHA-256) to files in the Unity project's `Assets/StreamingAssets`; the bundled Noto Sans KR font is also byte-for-byte identical to the Unity project's font and carries its OFL notice. The three Ogg Theora videos are converted copies of the project's original museum MP4/MOV videos. The Unity repository README identifies Art Valley Astronomical Science Museum as the rights holder for this photo booth's content.

These are content assets, not software source, and are excluded from the root MIT license. The Godot project contains no Unity runtime or TextMesh Pro/Unity Asset Store package files; the Unity checkout's separate TextMesh Pro files are not dependencies of this Godot app. This audit shows what is present and where the matching files came from; it is not a substitute for the museum's asset records. Publicly uploading the original media is a separate act of distribution and should be approved by the museum rights holder.

## Package checks

The Windows package carries the project MIT license and notices for Godot and its bundled third-party components, cloudflared, and Noto Sans KR. A successful build regenerates the Godot notice from the installed engine, so update the engine and rebuild together when changing Godot versions.