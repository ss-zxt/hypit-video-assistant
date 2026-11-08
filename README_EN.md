# Hypit Video Remake Assistant

**A local video-breakdown assistant for Windows**: paste a video link (or pick a
local video file) and it fetches the clip, cuts frame grids, reads them one by
one with a **vision model running on your own machine**, and produces a shot
breakdown draft, `DRAFT_NOTES.md`. Everything runs locally — your videos are
never sent to a cloud service.

The fetch engine is yt-dlp (driven via omniget-cli), so this is **not
TikTok-only**: yt-dlp supports well over a thousand sites — YouTube, Bilibili,
Instagram, X and more all work by pasting the link. Field-tested notes:
TikTok is the most reliable; Bilibili works up to 1080p without login;
YouTube depends on your network and login state, and some videos need
cookies; Douyin requires cookies imported from a real browser first (no
one-click import built in yet). Where scripts and the UI say "TikTok", that
is naming only — the download logic treats every link the same.

> **Free edition**: this assistant is the **free** version. It only does
> the "break down into prompts" step — it produces the breakdown draft
> as an MD file and **does not generate video itself**. Upload the MD
> file to another AI agent (e.g. Muse) to produce the video; for
> direct video generation, subscribe to Hypit's related services
> separately.

[中文版](README.md) · The Linux edition lives in a separate project:
[hypit-ollama-kit](https://github.com/ss-zxt/hypit-ollama-kit)

If this project helps you, a ⭐ star is appreciated!

---

## What it is

The first step of remaking a short video is the breakdown: understanding the
source clip along its timeline — what is on screen, how the camera moves,
where the beats are. It is slow, eye-straining work. This assistant turns it
into a pipeline:

```
Link / local video
   → 1. Fetch (omniget-cli + yt-dlp download, or a local file as-is)
   → 2. Frame & archive (Hypit: frame grids at 0.5s intervals + reference pack)
   → 3. Read every grid (local Ollama vision model, notes saved per grid)
   → 4. Merge into a DRAFT_NOTES.md draft
```

Installed components (official sources only, SHA-256 verified at install):

| Component | Role | Version |
|---|---|---|
| Hypit (skill + CLI) | Frame grids, tiling, reference archive | 0.3.1 |
| Ollama | Local model runtime (an existing install is reused) | 0.40.14 |
| qwen3-vl (vision model) | Per-grid image reading, tier picked by hardware | by hardware |
| FFmpeg | Video processing | 8.1.2 |
| omniget-cli + yt-dlp | Clip fetching | 0.14.0 / 2026.10.26 |

**Scope and limits (read this first)**: a small local model's **per-grid notes
are usable raw material**, but its self-written "merged breakdown" frequently
invents content (repeatedly observed in testing — treat it as unreliable).
The intended workflow: use the draft as raw material, and let a human or a
stronger model check it against the source clip and write the final prompt
pack. The assistant saves you the frame-by-frame note-taking; it does not
replace the final judgment.

**Privacy**: breakdowns run fully offline on your machine. Networking happens
only when installing components / pulling models and when downloading a video
you provided.

## Requirements

- Windows 10 / 11 (64-bit)
- RAM ≥ 8 GB (decides the model tier below); ~10 GB of free disk
- A discrete GPU helps a lot (much faster reading); CPU-only works, slower

Model tier is selected automatically from your hardware:

| Condition | Model |
|---|---|
| RAM ≥ 32 GB or VRAM ≥ 16 GB | qwen3-vl 14B class |
| RAM ≥ 16 GB or VRAM ≥ 8 GB | qwen3-vl 8B class |
| RAM ≥ 8 GB | qwen3-vl 4B (instruct) |
| Below that | small fallback model (limited reading quality) |

Note: on a high-RAM machine without a discrete GPU, a large model runs on
CPU only — it works, but slowly. That is expected.

## Installation

1. Download this repository as a ZIP and extract it anywhere (a D: drive is
   a good home).
2. Double-click **`windows\install.bat`** and let it finish. An existing
   Ollama installation is reused, never overwritten. Every step reports in
   Chinese-friendly logs; a failure stops with the reason.
3. Double-click **`windows\verify.bat`** to verify: **ALL CHECKS PASSED**
   (11 checks, including a real inference smoke test) means you are done.
4. To uninstall: run `windows\uninstall.ps1` in PowerShell. It removes only
   what this assistant installed — your Ollama and data folders stay.

Tip: if your proxy redirects the Ollama registry to a non-public address,
Ollama refuses the model pull (its own safety rule). Use another network, or
if you already have a suitable model, install with `-Model <model name>` to
skip the pull.

## Usage

### Graphical interface (recommended)

1. **First time**: double-click `windows\assistant\video-draft-gui.bat`.
   Once the window opens, a shortcut with the app icon, "**Hypit本地助手**",
   is generated automatically in the repository root.
2. **After that**: just double-click the root shortcut. Startup shows **no
   console window at all**; the taskbar shows only the app window with its
   own icon.
3. Paste a video link into the input box (or use "选文件..." for a local
   video), click "**开始生成初稿**" and watch the live log. You can stop
   midway — notes for grids already read are kept in the project folder.
4. When a run finishes, three buttons light up:
   - **打开初稿 DRAFT_NOTES.md** — open the draft;
   - **打开项目文件夹** — the project folder with frames and per-grid notes;
   - **复制MD文件** — copies in two formats at once: paste into a chat/text
     box to get the full draft text, paste into a folder to get the .md
     file itself (handy for handing the draft to an AI or a colleague).
5. The status line reports your hardware: a discrete GPU is named when one
   is present; otherwise it warns that reading is CPU-only and slow.

Moved the folder and the shortcut broke? Double-click `video-draft-gui.bat`
once — it rewrites the shortcut for the new location. If the root shortcut
never appears, double-click `windows\assistant\create-shortcut.bat`: its
window stays open and prints exactly where the shortcut was written.

### Command line

Double-click `windows\assistant\video-draft.bat` and paste a link when
asked, or **drag a video file onto** `video-draft.bat` to start directly.

### Where data and output live

- With a D: drive, data defaults to **`D:\HypitData`** (otherwise your user
  profile). To change it, set the `HYPIT_DATA_DIR` environment variable.
- Downloaded videos: `<data dir>\downloads\tiktok`
- One project folder per video: `<data dir>\projects\<name>`, containing
  `DRAFT_NOTES.md` (the draft), the per-grid notes, frame grids and the
  archived source clip.

## FAQ

- **Reading is slow**: without a discrete GPU, reads are CPU-only and a few
  minutes per grid is normal. The completion-first fallback automatically
  splits or shrinks a stubborn grid and retries — it will not hang forever.
- **The merged section disagrees with the per-grid notes**: trust the
  per-grid notes (see "Scope and limits"); the merge is a reference only.
- **Model download failed during install**: check your network/proxy, or
  install any qwen3-vl model first and re-run the installer with `-Model`.
- **The taskbar icon looks wrong**: overwrite with the latest version,
  close the old window and reopen. The current version registers its own
  app identity, so the PowerShell icon no longer appears.

## Sources and license

All components come from official release channels; versions and SHA-256
values are pinned in `windows\versions.psd1`. The scripts in this repository
are MIT-licensed (see `LICENSE`); each component keeps its own license.
