import AppKit
import SwiftUI

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
    exit(0)
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var model: PracticeModel!
    var pending: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = PracticeModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 870), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = "Awk Piano · Piano, at your pace"
        window.minSize = NSSize(width: 1040, height: 790)
        window.contentView = NSHostingView(rootView: AwkPianoView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        if !pending.isEmpty { model.importURLs(pending); pending = [] }
    }
    func application(_ application: NSApplication, open urls: [URL]) { if let model { model.importURLs(urls) } else { pending.append(contentsOf: urls) } }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.pause() }
    @objc func importSong() { model.importFiles() }
    @objc func help() { model.showHelp = true }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName:"Awk Piano", .applicationVersion:"1.0.0", .credits:NSAttributedString(string: "Piano, at your pace.\nA local MIDI piano-learning game for Mac.")]) }
    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "About Awk Piano", action: #selector(about), keyEquivalent: ""); aboutItem.target = self; appMenu.addItem(aboutItem)
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit Awk Piano", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); menu.addItem(appItem)
        let file = NSMenuItem(); let fileMenu = NSMenu(title: "File"); file.submenu = fileMenu
        let importItem = NSMenuItem(title: "Add MIDI Song…", action: #selector(importSong), keyEquivalent: "o"); importItem.target = self; fileMenu.addItem(importItem)
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); menu.addItem(file)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit"); edit.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"); editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"); editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"); menu.addItem(edit)
        let helpItem = NSMenuItem(); let helpMenu = NSMenu(title: "Help"); helpItem.submenu = helpMenu
        let item = NSMenuItem(title: "How to Play Awk Piano", action: #selector(help), keyEquivalent: "?"); item.target = self; helpMenu.addItem(item); menu.addItem(helpItem)
        NSApp.mainMenu = menu
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
