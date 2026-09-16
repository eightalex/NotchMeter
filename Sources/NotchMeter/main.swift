import AppKit

/// `--dump` друкує те саме, що застосунок показав би в notch, але у терміналі —
/// зручно для перевірки провайдерів без запуску інтерфейсу.
if CommandLine.arguments.contains("--dump") {
    await Diagnostics.run()
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let directory = CommandLine.arguments.count > index + 1
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1])
        : FileManager.default.temporaryDirectory
    await Snapshot.render(to: directory)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
