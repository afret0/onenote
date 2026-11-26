import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var pasteKeyMonitor: Any?
  private var commandSeenInEventStream = false
  private var pasteChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    self.isRestorable = false
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    _ = flutterViewController.view
    flutterViewController.viewWillAppear()
    self.initialFirstResponder = flutterViewController.view
    self.makeFirstResponder(flutterViewController.view)

    RegisterGeneratedPlugins(registry: flutterViewController)

    pasteChannel = FlutterMethodChannel(
      name: "onenote/synthetic_paste",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .keyUp, .flagsChanged]
    ) { [weak self] event in
      guard let self = self else { return event }
      if event.type == .flagsChanged {
        self.commandSeenInEventStream = event.modifierFlags.contains(.command)
        return event
      }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard flags.contains(.command),
        let key = event.charactersIgnoringModifiers?.lowercased(),
        key == "v" || key == "a",
        !self.commandSeenInEventStream
      else { return event }
      if event.type == .keyDown {
        let method = key == "v" ? "paste" : "selectAll"
        NSLog("onenote: synthetic Cmd+\(key.uppercased()) intercepted, dispatching \(method)")
        self.pasteChannel?.invokeMethod(method, arguments: nil)
      }
      return nil
    }

    super.awakeFromNib()
  }

  override func becomeKey() {
    super.becomeKey()
    if let flutterView = contentViewController?.view,
      firstResponder !== flutterView
    {
      makeFirstResponder(flutterView)
    }
  }

  deinit {
    if let monitor = pasteKeyMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
