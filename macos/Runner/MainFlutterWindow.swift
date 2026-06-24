import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  // Minimum on-screen size of the main shell window (ADR 0021). Below this the
  // adaptive chrome (title bar overflow, icon-only tabs) and content would be
  // crushed; 720x520 keeps nav rail + sidebar + one usable content panel visible.
  // 720 also sits just under the title-bar overflow breakpoint (800) so the most
  // collapsed adaptive state stays reachable by resizing to the minimum.
  static let mainMinSize = NSSize(width: 720, height: 520)

  // Minimum size of a detached terminal window (ADR 0020 / 0021). A single
  // terminal stays usable down to this; below it the view would be unreadable.
  static let detachedMinSize = NSSize(width: 420, height: 280)

  // Hard floor on the window size (ADR 0021). `minSize` clamps interactive
  // edge-drag resizing, but programmatic / Accessibility resizes bypass it;
  // clamping every setFrame guarantees the window can never be sized below the
  // minimum by ANY path. Only the lower bound is touched, so maximise / zoom
  // (which set a larger frame) are unaffected.
  private func _clampedToMin(_ frameRect: NSRect) -> NSRect {
    var r = frameRect
    r.size.width = max(r.size.width, MainFlutterWindow.mainMinSize.width)
    r.size.height = max(r.size.height, MainFlutterWindow.mainMinSize.height)
    return r
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(_clampedToMin(frameRect), display: flag)
  }

  override func setFrame(
    _ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool
  ) {
    super.setFrame(
      _clampedToMin(frameRect), display: displayFlag, animate: animateFlag)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Clamp the main window so it can never be dragged to an unusable sliver.
    self.minSize = MainFlutterWindow.mainMinSize

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register all plugins for every detached window's engine too, so a detached
    // terminal window (ADR 0020) can render and proxy I/O back to this window.
    // Also clamp each detached NSWindow's minimum size (ADR 0021): the plugin
    // sets `window.contentViewController` before this callback fires, so
    // `controller.view.window` is the live NSWindow; if it isn't attached yet we
    // defer to the next runloop tick.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      let minSize = MainFlutterWindow.detachedMinSize

      func configure(_ window: NSWindow) {
        window.minSize = minSize
        // Frameless detached terminal window (ADR 0024): hide the native title
        // bar so the Flutter title row is the chrome; traffic lights stay inset
        // over the content.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
      }

      if let window = controller.view.window {
        configure(window)
      } else {
        DispatchQueue.main.async {
          if let window = controller.view.window { configure(window) }
        }
      }
    }

    super.awakeFromNib()
  }
}
