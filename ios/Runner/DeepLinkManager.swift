import Foundation
import Flutter

class DeepLinkManager {
  static let shared = DeepLinkManager()
  private init() {}

  private var channel: FlutterMethodChannel?
  private var pendingLink: String?

  func configure(channel: FlutterMethodChannel) {
    self.channel = channel
    // If we already have a pending link captured before Flutter was ready, try dispatching now
    dispatchPendingIfAny()
  }

  func storePendingLink(url: URL) {
    guard shouldHandle(url: url) else { return }
    pendingLink = url.absoluteString
  }

  func consumePendingLink() -> String? {
    defer { pendingLink = nil }
    return pendingLink
  }

  func handle(url: URL) {
    guard shouldHandle(url: url) else { return }
    let link = url.absoluteString
    if let channel = channel {
      channel.invokeMethod("onLink", arguments: ["url": link])
    } else {
      pendingLink = link
    }
  }

  private func dispatchPendingIfAny() {
    guard let link = pendingLink, let channel = channel else { return }
    channel.invokeMethod("onLink", arguments: ["url": link])
    pendingLink = nil
  }

  private func shouldHandle(url: URL) -> Bool {
    // Accept:
    // - https://smartdisplay.mareo.ai/launch.html?... or /connect
    // - https://m.smartdisplay.mareo.ai/launch.html?... or /connect
    // - smartdisplay://connect?... (custom scheme)
    if let scheme = url.scheme?.lowercased() {
      if scheme == "http" || scheme == "https" {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let hostOk = host == "smartdisplay.mareo.ai" || host == "m.smartdisplay.mareo.ai"
        let pathOk = path == "/launch.html" || path == "/connect"
        return hostOk && pathOk
      }
      if scheme == "smartdisplay" {
        // For custom scheme, host is often used as the first segment, e.g. smartdisplay://connect
        let host = (url.host ?? "").lowercased()
        let pathSeg = url.pathComponents.dropFirst().first?.lowercased() // if form like smartdisplay:/connect
        return host == "connect" || pathSeg == "connect"
      }
    }
    return false
  }
}
