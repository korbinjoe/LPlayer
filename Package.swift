// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LPlayer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LPlayer", targets: ["PalmPlayer"])],
    targets: [
        .systemLibrary(name: "CMpv", pkgConfig: "mpv", providers: [.brew(["mpv"])]),
        .executableTarget(name: "PalmPlayer", dependencies: ["CMpv"], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("OpenGL"), .linkedFramework("CoreVideo"), .linkedFramework("AVFoundation")
        ]),
        .testTarget(name: "PalmPlayerTests", dependencies: ["PalmPlayer"])
    ]
)
