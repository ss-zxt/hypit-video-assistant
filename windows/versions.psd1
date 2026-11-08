@{
    # Pinned versions for the Windows build of the Hypit + Ollama kit.
    # Verified 2026-11-08 against the official releases (see SOURCES.md).
    HypitVersion        = '0.3.1'
    HypitNpmIntegrity   = 'sha512-FI54GPQRB9uXSTRmCt8fngzWH/YEEasOIuYhwsEh9G2v92L50N/TdcMiLgDT1KfRjt+C1/HXcG28Bai6HMEDQQ=='

    OllamaVersion       = '0.40.14'
    OllamaAsset         = 'ollama-windows-amd64.zip'
    OllamaAssetSha256   = '65d68cade6cf6375f398b518224f8c8a15e062387f38cf477abfc848de7e7e29'
    OllamaUrl           = 'https://github.com/ollama/ollama/releases/download/v0.40.14/ollama-windows-amd64.zip'

    # Windows default model policy: 'auto' = pick by RAM / GPU VRAM at
    # install time (see select-model.ps1). Personal computers should not
    # be stuck with the cloud-VM default qwen3:1.7b.
    DefaultModelPolicy  = 'auto'

    FfmpegVersion       = '8.1.2'
    FfmpegAsset         = 'ffmpeg-8.1.2-essentials_build.zip'
    FfmpegAssetSha256   = 'db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec'
    FfmpegUrl           = 'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-8.1.2-essentials_build.zip'

    OmnigetVersion      = '0.14.0'
    OmnigetAsset        = 'omniget-cli-0.14.0-x86_64-pc-windows-msvc.zip'
    OmnigetAssetSha256  = '0919da175a95528402dc0073d85e01bfb6d20402f1d10713ebece6e2156c068a'
    OmnigetUrl          = 'https://github.com/OpenSelena/omniget/releases/download/v0.14.0/omniget-cli-0.14.0-x86_64-pc-windows-msvc.zip'

    YtdlpVersion        = '2026.10.26'
    YtdlpAsset          = 'yt-dlp.exe'
    YtdlpAssetSha256    = 'f5389d3698ecde4ef06f4e6b1ce0294fe9ac1396228c8990b8d3416d6d177a7d'
    YtdlpUrl            = 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.10.26/yt-dlp.exe'
}
