// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiftrWorkoutActivityKit",
    platforms: [.iOS("16.2")],
    products: [
        .library(name: "LiftrWorkoutActivityKit", targets: ["LiftrWorkoutActivityKit"])
    ],
    targets: [
        .target(
            name: "LiftrWorkoutActivityKit"
        )
    ]
)
