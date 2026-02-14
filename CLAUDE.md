# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Moonlight is an open-source game streaming client for iOS, tvOS, and visionOS. It connects to Sunshine/NVIDIA GameStream hosts to stream games over the network. The core streaming protocol is implemented in C (`moonlight-common-c` submodule), with platform UI in Objective-C (iOS/tvOS) and SwiftUI (visionOS).

## Build Commands

Build from command line (or use Xcode GUI with the corresponding scheme):
```bash
# iOS
xcodebuild -scheme Moonlight -sdk iphoneos -configuration Debug

# tvOS
xcodebuild -scheme "Moonlight TV" -sdk appletvos -configuration Debug

# visionOS
xcodebuild -scheme "Moonlight Vision" -sdk xros -configuration Debug

# Simulator variants
xcodebuild -scheme Moonlight -sdk iphonesimulator -configuration Debug
xcodebuild -scheme "Moonlight TV" -sdk appletvsimulator -configuration Debug
xcodebuild -scheme "Moonlight Vision" -sdk xrsimulator -configuration Debug
```

## Setup Requirements

- Clone with `--recursive` for `moonlight-common-c` submodule
- Create `Configurations/credentials.xcconfig` with `PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM` for device builds
- Pre-built static libraries for FFmpeg, Opus, and SDL3 are committed in `libs/`

## Architecture

### Platform Targets

| Target | Platform | UI Framework | Min Deployment |
|--------|----------|-------------|----------------|
| Moonlight | iOS 12.0+ | UIKit + Storyboards | iPhone & iPad |
| Moonlight TV | tvOS | UIKit | Apple TV |
| Moonlight Vision | xrOS 1.2+ | SwiftUI + RealityKit | Apple Vision Pro |

### Layer Structure

- **UI Layer**: `Limelight/ViewControllers/` (iOS/tvOS MVC with storyboards: iPhone.storyboard, iPad.storyboard), `Moonlight Vision/` (visionOS SwiftUI)
- **Networking**: `Limelight/Network/` — host discovery (`DiscoveryManager`, `MDNSManager`), HTTP communication (`HttpManager`), pairing (`PairManager`), Wake-on-LAN
- **Streaming**: `Limelight/Stream/` — `StreamManager` orchestrates sessions, `VideoDecoderRenderer` uses VideoToolbox for hardware decoding
- **Input**: `Limelight/Input/` — game controller support (`ControllerSupport`), keyboard, touch (relative/absolute), haptics
- **Crypto**: `Shared/Crypto/` — `CryptoManager` (Swift, CryptoKit/CommonCrypto/Security.framework) for certificates, encryption, key management; `CertificateGenerator` for RSA-2048 X.509 cert generation via swift-certificates
- **Data**: `Limelight/Database/` — Core Data persistence with `DataManager`, 18 schema migration versions
- **Core Protocol**: `moonlight-common/moonlight-common-c/` — C library implementing GameStream/RTP protocol, video/audio depacketization, RTSP

### Obj-C / Swift Interop

- iOS/tvOS are primarily Objective-C with bridging header at `Limelight/Input/Moonlight-Bridging-Header.h`
- visionOS target uses Swift/SwiftUI, wrapping shared Obj-C classes via `Moonlight Vision/Moonlight-Bridging-Header.h`
- `AppController` bridges Obj-C managers (like `DiscoveryManager`) to SwiftUI's `HostsController`

### Callback Pattern

Async operations use delegate/callback protocols extensively: `DiscoveryCallback`, `PairCallback`, `HostCallback`, `AppCallback`, `ConnectionCallbacks`. `MainFrameViewController` implements most of these as a central hub on iOS/tvOS.

### Multi-Platform Conditional Compilation

```objc
#if TARGET_OS_TV    // tvOS-specific code
#if !TARGET_OS_TV   // iOS-only code (settings, help screens)
```

## Third-Party Libraries (in `libs/`)

All are pre-compiled static libraries with per-platform slices (iphoneos, iphonesimulator, appletvos, appletvsimulator, xros, xrsimulator):
- **SDL3** — as xcframework
- **FFmpeg** — video codec support (libavutil, libavformat, libavcodec)
- **Opus** — audio codec (libopus)

Library search paths are configured in `Configurations/paths.xcconfig`.

## Swift Packages

- **swift-certificates** (SPM) — X.509 certificate generation, RSA keys via `_CryptoExtras`, ASN.1 parsing via `SwiftASN1`
- **RealityKitContent** (local) — visionOS spatial content assets

## Key Configuration Files

- `Configurations/ios.xcconfig`, `tvos.xcconfig`, `visionos.xcconfig` — per-platform build settings
- `Configurations/paths.xcconfig` — library and header search paths
- `Configurations/credentials.xcconfig` — bundle ID and team (gitignored)
- `Limelight/Limelight-Info.plist` — iOS/tvOS app config (Bonjour, Bluetooth, controllers)
