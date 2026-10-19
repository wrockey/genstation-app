#!/usr/bin/env python3
"""Render the production thumbnail view in isolation; no real app state or provider calls.
Minimal domain/AppState adapters supply only the fields used by the view. The 16px
fixture needs no downscaling. --baseline uses HEAD to demonstrate the old failure.
Requires macOS with a GUI session and the Swift compiler.
"""
import subprocess
import sys
import tempfile
from pathlib import Path
scratch_owner = tempfile.TemporaryDirectory(prefix="genstation-thumbnail-")
scratch = Path(scratch_owner.name)
source = Path('GenStation/Library/HistoryTreeNode.swift').read_text()
if '--baseline' in sys.argv:
    source = subprocess.check_output(['git', 'show', 'HEAD:GenStation/Library/HistoryTreeNode.swift'], text=True)
start = source.index('struct HistoryThumbnailSource:') if 'struct HistoryThumbnailSource:' in source else source.index('struct LazyThumbnailView:')
view = source[start:source.index('private extension HistoryEntry {')]
preamble = '''import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

typealias PlatformImage = NSImage
struct HistoryItem { var id = UUID(); var imagePath: String?; var status: GenerationStatus?; var date = Date(); var videoHasAudio: Bool? }
enum GenerationStatus: Hashable { case queued, completed }
final class AppState: ObservableObject { let settings = Settings() }
final class Settings { var outputDirectory: URL? }
enum DS { enum Radius { static let standard: CGFloat = 8 } }
enum Log { static func debug(_ message: String) {} }
extension Image { init(platformImage: NSImage) { self.init(nsImage: platformImage) } }
extension NSImage { convenience init?(platformData: Data) { self.init(data: platformData) }; func downscaled(toMaxPixels: Int) -> NSImage { self } }
final class Fixture: ObservableObject { @Published var item = HistoryItem(imagePath: nil, status: .queued) }
struct FixtureView: View {
    @ObservedObject var fixture: Fixture
    let app: AppState
    var body: some View { LazyThumbnailView(item: fixture.item).environmentObject(app).frame(width: 50, height: 50) }
}
'''
main = '''
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixture = Fixture()
let hosting = NSHostingView(rootView: FixtureView(fixture: fixture, app: AppState()))
let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 50, height: 50), styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = hosting
window.orderFront(nil)
func spin() { let end = Date().addingTimeInterval(1.5); while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.03)) } }
func isRed() -> Bool {
    hosting.layoutSubtreeIfNeeded()
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB) else { return false }
    return color.redComponent > 0.8 && color.greenComponent < 0.2 && color.blueComponent < 0.2
}
spin()
let before = isRed()
fixture.item.imagePath = CommandLine.arguments[1]
fixture.item.status = .completed
spin()
let completed = isRed()
fixture.item.imagePath = nil
fixture.item.status = .queued
spin()
let cleared = !isRed()
print("placeholder_not_red=\\(!before) completed_red_without_reappear=\\(completed) old_thumbnail_cleared=\\(cleared)")
window.orderOut(nil)
exit(!before && completed && cleared ? 0 : 1)
'''
(scratch / 'harness.swift').write_text(preamble + view + main)
import struct, zlib
chunk=lambda k,p:struct.pack('>I',len(p))+k+p+struct.pack('>I',zlib.crc32(k+p))
(scratch / 'red.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',16,16,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+b'\xff\0\0'*16)*16))+chunk(b'IEND',b''))

compiled = subprocess.run(['swiftc', str(scratch / 'harness.swift'), '-o', str(scratch / 'harness')], capture_output=True, text=True)
if compiled.returncode:
    print(compiled.stderr)
    sys.exit(compiled.returncode)
result = subprocess.run([str(scratch / 'harness'), str(scratch / 'red.png')], timeout=30)
sys.exit(result.returncode)
