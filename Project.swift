import ProjectDescription

// MARK: - moonlight-common-c (static library)

let moonlightCommon = Target.target(
    name: "moonlight-common",
    destinations: [.iPhone, .iPad, .appleTv, .appleVision],
    product: .staticLibrary,
    bundleId: "com.moonlight-stream.moonlight-common",
    sources: [
        "moonlight-common/moonlight-common-c/src/**",
        "moonlight-common/moonlight-common-c/enet/*.c",
        "moonlight-common/moonlight-common-c/reedsolomon/**",
    ],
    headers: .headers(
        public: [
            "moonlight-common/moonlight-common-c/src/Limelight.h",
        ]
    ),
    settings: .settings(base: [
        "HEADER_SEARCH_PATHS": [
            "$(SRCROOT)/moonlight-common/moonlight-common-c/src",
            "$(SRCROOT)/moonlight-common/moonlight-common-c/enet/include",
            "$(SRCROOT)/moonlight-common/moonlight-common-c/reedsolomon",
        ],
        "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
    ])
)

// MARK: - Moonlight App

let moonlightApp = Target.target(
    name: "Moonlight",
    destinations: [.iPhone, .iPad, .appleTv, .appleVision],
    product: .app,
    bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
    infoPlist: .extendingDefault(with: [
        "CADisableMinimumFrameDuration": true,
        "CADisableMinimumFrameDurationOnPhone": true,
        "CFBundleDisplayName": "Moonlight",
        "GCSupportedGameControllers": [
            ["ProfileName": "ExtendedGamepad"],
        ],
        "GCSupportsControllerUserInteraction": true,
        "ITSAppUsesNonExemptEncryption": false,
        "LSSupportsGameMode": true,
        "LSApplicationCategoryType": "public.app-category.games",
        "NSAppTransportSecurity": [
            "NSAllowsArbitraryLoads": true,
            "NSAllowsArbitraryLoadsInWebContent": true,
            "NSAllowsLocalNetworking": true,
        ],
        "NSBluetoothAlwaysUsageDescription":
            "Bluetooth access allows Moonlight to connect to Citrix X1 mice.",
        "NSBluetoothPeripheralUsageDescription":
            "Bluetooth access allows Moonlight to connect to Citrix X1 mice.",
        "NSBonjourServices": ["_nvstream._tcp"],
        "NSLocalNetworkUsageDescription":
            "Moonlight uses the local network to connect to your gaming PC for streaming.",
        "UIApplicationSupportsIndirectInputEvents": true,
        "UIRequiresFullScreen": true,
        "UILaunchToFullScreenByDefault": true,
        "UIStatusBarHidden": true,
        "UIViewControllerBasedStatusBarAppearance": false,
        "UIUserInterfaceStyle": "Dark",
        "UILaunchScreen": [:],
    ]),
    sources: [
        // Shared SwiftUI layer
        "Shared/**",
        // Streaming
        "Limelight/Stream/**",
        // Input handling
        "Limelight/Input/**",
        // Crypto
        "Limelight/Crypto/**",
        // Utilities
        "Limelight/Utility/**",
        // StreamFrameViewController (UIViewControllerRepresentable wrapper)
        "Limelight/ViewControllers/StreamFrameViewController.h",
        "Limelight/ViewControllers/StreamFrameViewController.m",
        // Network (needed by StreamManager)
        "Limelight/Network/HttpManager.h",
        "Limelight/Network/HttpManager.m",
        "Limelight/Network/HttpRequest.h",
        "Limelight/Network/HttpRequest.m",
        "Limelight/Network/HttpResponse.h",
        "Limelight/Network/HttpResponse.m",
        "Limelight/Network/ServerInfoResponse.h",
        "Limelight/Network/ServerInfoResponse.m",
        // Database models (needed by Network/Streaming layer)
        "Limelight/Database/DataManager.h",
        "Limelight/Database/DataManager.m",
        "Limelight/Database/TemporaryHost.h",
        "Limelight/Database/TemporaryHost.m",
        "Limelight/Database/TemporaryApp.h",
        "Limelight/Database/TemporaryApp.m",
        "Limelight/Database/TemporarySettings.h",
        "Limelight/Database/TemporarySettings.m",
    ],
    resources: [
        "Limelight/Images.xcassets",
    ],
    entitlements: "Moonlight.entitlements",
    dependencies: [
        .target(name: "moonlight-common"),
        .external(name: "_CryptoExtras"),
        .external(name: "X509"),
        .sdk(name: "AudioToolbox", type: .framework),
        .sdk(name: "AVFoundation", type: .framework),
        .sdk(name: "CoreMedia", type: .framework),
        .sdk(name: "GameController", type: .framework),
        .sdk(name: "Security", type: .framework),
        .sdk(name: "VideoToolbox", type: .framework),
    ],
    settings: .settings(
        base: [
            "SWIFT_OBJC_BRIDGING_HEADER": "Shared/Moonlight-Bridging-Header.h",
            "GCC_PREFIX_HEADER": "Limelight/Limelight-Prefix.pch",
            "GCC_PRECOMPILE_PREFIX_HEADER": "YES",
            "CLANG_ENABLE_MODULES": "YES",
            "SWIFT_VERSION": "6.0",
            "SWIFT_OBJC_INTERFACE_HEADER_NAME": "Moonlight-Swift.h",
            "HEADER_SEARCH_PATHS": [
                "$(inherited)",
                "$(SRCROOT)/Limelight/Stream",
                "$(SRCROOT)/Limelight/Input",
                "$(SRCROOT)/Limelight/Crypto",
                "$(SRCROOT)/Limelight/Utility",
                "$(SRCROOT)/Limelight/Network",
                "$(SRCROOT)/Limelight/Database",
                "$(SRCROOT)/Limelight/ViewControllers",
                "$(SRCROOT)/Shared/Audio",
            ],
            "OTHER_LDFLAGS": [
                "$(inherited)",
                "-lxml2",
                "-lopus",
                "-lavutil",
                "-lavformat",
                "-lavcodec",
                "-lc++",
            ],
            "SWIFT_INCLUDE_PATHS": [
                "$(inherited)",
                "$(SRCROOT)/Shared/Networking/XML/Clibxml2",
            ],
            "MARKETING_VERSION": "9.0.2",
            "CURRENT_PROJECT_VERSION": "1",
            "SUPPORTS_MACCATALYST": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME": "",
        ],
        configurations: [
            .debug(name: "Debug", xcconfig: "Configurations/paths.xcconfig"),
            .release(name: "Release", xcconfig: "Configurations/paths.xcconfig"),
        ]
    )
)

// MARK: - Project

let project = Project(
    name: "Moonlight",
    settings: .settings(
        configurations: [
            .debug(name: "Debug", xcconfig: "Configurations/credentials.xcconfig"),
            .release(name: "Release", xcconfig: "Configurations/credentials.xcconfig"),
        ]
    ),
    targets: [
        moonlightApp,
        moonlightCommon,
    ]
)
