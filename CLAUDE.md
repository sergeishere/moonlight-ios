# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Moonlight is an open-source game streaming client for iOS, tvOS, and visionOS. It connects to Sunshine/NVIDIA GameStream hosts to stream games over the network. The core streaming protocol is implemented in C (`moonlight-common-c` submodule), with platform UI in Objective-C (iOS/tvOS) and SwiftUI (visionOS).

## Build System

The project uses **Tuist** (`Project.swift`) as the single source of build configuration.

```bash
# Generate Xcode project
tuist generate

# Build iOS
xcodebuild -scheme Moonlight -sdk iphoneos -configuration Debug

# Build iOS Simulator
xcodebuild -scheme Moonlight -sdk iphonesimulator -configuration Debug
```

## Setup Requirements

- Clone with `--recursive` for `moonlight-common-c` submodule
- Create `Configurations/credentials.xcconfig` with `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` for device builds
- Pre-built static libraries for FFmpeg, Opus, and SDL3 are committed in `libs/`

## Architecture

### Layer Structure

- **UI Layer**: `Limelight/ViewControllers/` (iOS/tvOS MVC with storyboards: iPhone.storyboard, iPad.storyboard)
- **Networking**: `Limelight/Network/` — host discovery (`DiscoveryManager`, `MDNSManager`), HTTP communication (`HttpManager`), pairing (`PairManager`), Wake-on-LAN
- **Streaming**: `Limelight/Stream/` — `StreamManager` orchestrates sessions, `VideoDecoderRenderer` uses VideoToolbox for hardware decoding
- **Input**: `Limelight/Input/` — game controller support (`ControllerSupport`), keyboard, touch (relative/absolute), haptics
- **Crypto**: `Shared/Crypto/` — `CryptoManager` (Swift, CryptoKit/CommonCrypto/Security.framework) for certificates, encryption, key management; `CertificateGenerator` for RSA-2048 X.509 cert generation via swift-certificates
- **Data**: `Limelight/Database/` — Core Data persistence with `DataManager`, 18 schema migration versions
- **Core Protocol**: `moonlight-common/moonlight-common-c/` — C library implementing GameStream/RTP protocol, video/audio depacketization, RTSP

### Obj-C / Swift Interop

- Bridging header: `Shared/Moonlight-Bridging-Header.h` (configured in `Project.swift`)

### Callback Pattern

Async operations use delegate/callback protocols extensively: `DiscoveryCallback`, `PairCallback`, `HostCallback`, `AppCallback`, `ConnectionCallbacks`. `MainFrameViewController` implements most of these as a central hub on iOS/tvOS.

### Multi-Platform Conditional Compilation

```objc
#if TARGET_OS_TV    // tvOS-specific code
#if !TARGET_OS_TV   // iOS-only code (settings, help screens)
```

## Third-Party Libraries (in `libs/`)

All are pre-compiled static libraries with per-platform slices:
- **SDL3** — as xcframework
- **FFmpeg** — video codec support (libavutil, libavformat, libavcodec)
- **Opus** — audio codec (libopus)

Library search paths are configured in `Configurations/paths.xcconfig`.

## Swift Packages

- **swift-certificates** (SPM) — X.509 certificate generation, RSA keys via `_CryptoExtras`, ASN.1 parsing via `SwiftASN1`
- **RealityKitContent** (local) — visionOS spatial content assets

## Key Configuration Files

- `Project.swift` — Tuist project definition (single source of truth for build config)
- `Configurations/paths.xcconfig` — library and header search paths
- `Configurations/credentials.xcconfig` — bundle ID and team (gitignored)
