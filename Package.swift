import PackageDescription

let package = Package(
    name: "SwiftHttp2",
    dependencies: [
        .Package(url: "https://github.com/nathanborror/hpack.swift.git", majorVersion: 0),
    ]
)
