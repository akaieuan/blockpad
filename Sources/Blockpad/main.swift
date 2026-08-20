import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--render-sample") {
    let output = index + 1 < arguments.count ? arguments[index + 1] : "./build/sample"
    SampleRender.run(outputDirectory: output)
    exit(0)
}

if let index = arguments.firstIndex(of: "--render-icon") {
    let output = index + 1 < arguments.count ? arguments[index + 1] : "./build/Blockpad.iconset"
    IconRender.run(outputDirectory: output)
    exit(0)
}

// Loads a known scene into the real store, so documentation screenshots show
// the app doing its job rather than an empty canvas.
if arguments.contains("--seed-demo") {
    SampleRender.seedDemoScene()
    exit(0)
}

let application = NSApplication.shared
// Top-level code is not implicitly main-actor in Swift 5 mode, but it does run
// on the main thread, so the assumption is sound.
let appDelegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = appDelegate
application.run()
