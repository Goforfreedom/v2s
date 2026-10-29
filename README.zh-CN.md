# v2s

<p align="center">
  <img src="Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" alt="v2s 应用图标" width="256" height="256">
</p>

<p align="center">
  <strong>macOS 上适用于会议、通话、直播和视频的实时双语字幕。</strong>
</p>

<p align="center">
  v2s 可以将麦克风输入或指定应用的音频转换成简洁的双行字幕条，让你在不离开当前屏幕的情况下，一边听原语言，一边看目标语言字幕。
</p>

<p align="center">
  <a href="https://franklioxygen.github.io/v2s/">官网</a>
  ·
  <a href="README.md">English Doc</a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/b65167ee-ae7e-4e37-8316-ebd200ae89a7" alt="Mar-20-2026 11-08-59">
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/449039ee-c329-426e-a55b-ab6660c56ca7" alt="Screenshot 2026-03-25 at 1 10 39 PM" width="500">
</p>

## 功能特性

- **菜单栏常驻应用**：启动后常驻于 macOS 菜单栏，随时可打开和控制字幕。
- **双语字幕悬浮条**：第一行显示翻译结果，第二行显示原始语音文本，便于快速对照。
- **灵活的音频输入**：既可使用麦克风，也可只捕获某个正在运行的 macOS 应用音频。
- **语音转写**：基于 Apple Speech 框架，优先使用本地语音识别。
- **本地翻译**：基于 Apple Translation 框架进行翻译处理。
- **AI 摘要**：基于 Apple Intelligence 对字幕记录进行智能摘要；当 Apple Intelligence 不可用时，自动回退到本地提取式摘要，同样可以快速掌握对话要点。
- **可调节的字幕样式**：支持调整悬浮条样式，保证字幕在真实工作场景中依然清晰可读。

## 输入与字幕语言

字幕语言来自 Apple 的 Translation 框架，因此这些选项会自动跟随系统与模型更新。输入语言为本地 Whisper 模型支持的语言，另有“自动识别”选项，可让识别模型逐段判断所说语言。界面会合并地区变体，但保留简体中文和繁体中文等有实际意义的文字变体。开始会话前，v2s 还会检查 Apple Translation 是否支持所选的源语言与目标语言组合。

## 隐私保护

- 无需账号，也没有云端后台、分析或遥测。
- v2s 没有云端后台，也不会把音频或字幕文本发送到自己的服务器。
- 翻译依赖 Apple 的本地 Translation 框架，部分语言包可能需要先在系统设置中下载。
- AI 翻译为可选项，默认关闭。开启后，字幕文本（不含音频）会发送给你选择的 API 服务商进行翻译；API Key 保存在 Mac 钥匙串中，不会写入设置文件。输入为“自动识别”时，AI 引擎也会从文本判断源语言。
- 语音识别在本地通过 WhisperKit 完成（Apple Silicon 上的设备端 CoreML 模型）：输入语言可指定具体语言，也可选择“自动识别”，由模型逐段判断所说语言。首次使用时，所选模型（极小约 80 MB、标准约 150 MB、小型约 500 MB）会从 HuggingFace 下载并缓存在本机；音频始终不出设备。模型缺失、加载失败或 Mac 为 Intel 芯片时，识别会自动回退到 Apple 语音识别，会话回退时设置里会显示提示。

## 快速开始

### 使用 Homebrew 安装

```bash
brew install --cask franklioxygen/v2s/v2s
```

v2s 尚未通过 Apple 公证，macOS 会在下载后将其隔离。执行一次下面的命令清除隔离标记，
之后即可正常启动：

```bash
xattr -dr com.apple.quarantine /Applications/v2s.app
```

如果之前手动安装过、`Applications` 里已经有 `v2s.app`，请加上 `--adopt`，让
Homebrew 接管现有副本，而不是因为无法覆盖而报错。

更新由应用内的更新器负责。如果希望改由 Homebrew 管理更新，可以运行
`brew upgrade --cask --greedy v2s`。

### 手动安装

1. 从 [Releases](https://github.com/franklioxygen/v2s/releases) 页面下载最新的 `.app.zip`。
2. 解压后将 `v2s.app` 移动到 `Applications` 文件夹。

### 首次运行

1. 启动 v2s，它会以图标形式出现在菜单栏中。
2. 选择输入源：麦克风或某个正在运行的应用。
3. 选择输入语言和字幕语言。
4. 点击 **Start**。

首次使用时，v2s 会请求以下权限：

- **Speech Recognition**：用于将音频转写为文本。
- **Microphone**：当输入源为麦克风时需要。
- **Audio Capture**：当输入源为其他应用时需要。

## 环境要求

- 语音转写和翻译功能需要 macOS 26 或更高版本
- 支持 Apple 芯片和 Intel Mac；可用的语音语言以及能否在本地识别，取决于具体 Mac 和所选语言。

## 从源码构建

```bash
git clone https://github.com/franklioxygen/v2s.git
cd v2s
open v2s.xcodeproj
```

也可以直接使用终端构建：

```bash
xcodebuild -project v2s.xcodeproj -scheme v2s -configuration Debug build
```

如需专门为 Intel Mac 构建：

```bash
swift build -c release --arch x86_64
```

## 许可证

MIT
