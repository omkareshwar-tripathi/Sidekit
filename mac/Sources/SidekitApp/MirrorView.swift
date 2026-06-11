import SwiftUI
import AppKit
import AVFoundation
import SidekitCore

/// The Mirror strip that rides at the top of the Shelf: a slim "Mirror" button when collapsed,
/// a live mirrored self-view (small or expanded) when open. Tapping the preview toggles size;
/// a top-right × collapses it (camera off). A source picker appears only when more than one
/// camera exists. If permission is denied, a compact inline prompt links to System Settings.
struct MirrorView: View {
    @ObservedObject var model: MirrorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.state)
    }

    @ViewBuilder private var content: some View {
        if model.permissionDenied {
            permissionPrompt
        } else if model.state == .fullScreen {
            fullScreenPlaceholder
        } else if model.state.cameraShouldRun {
            if model.devices.isEmpty {
                emptyPrompt
            } else {
                preview(height: model.state == .expanded ? 150 : 72)
            }
        } else {
            collapsedButton
        }
    }

    /// Shown in the windowed strip while the self-view is up on the full-display overlay: a compact
    /// row that names the state and offers a tap back to the windowed (`.expanded`) preview.
    private var fullScreenPlaceholder: some View {
        Button { model.toggleFullScreen() } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                Text("Mirror is full screen")
                Spacer()
                Text("Exit")
                    .foregroundStyle(DS.Palette.accent)
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassStrip()
    }

    /// Inline "camera blocked" notice with a jump to the Camera privacy pane.
    private var permissionPrompt: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "video.slash")
                .foregroundStyle(DS.Palette.textSecondary)
            Text("Camera access needed")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.accent)
        }
        .glassStrip()
    }

    /// Shown when the Mirror is open but no camera was discovered: a compact notice with a
    /// collapse control so the user can back out instead of staring at a black preview.
    private var emptyPrompt: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "video.slash")
                .foregroundStyle(DS.Palette.textSecondary)
            Text("No camera found")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            collapseControl
        }
        .glassStrip()
    }

    /// The collapsed affordance: a slim row that opens the Mirror (camera off until tapped).
    private var collapsedButton: some View {
        Button { model.tap() } label: {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "video.fill")
                Text("Mirror")
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassStrip()
    }

    /// The live preview at the given height: tap toggles small⇄expanded, with overlaid collapse
    /// control and (when >1 camera) source picker.
    private func preview(height: CGFloat) -> some View {
        CameraPreview(layer: model.previewLayer)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1))
            .overlay { edgeLightFrame }
            .contentShape(Rectangle())
            .onTapGesture { model.tap() }
            .overlay(alignment: .topTrailing) { collapseControl }
            .overlay(alignment: .topLeading) { sourcePicker }
            .overlay(alignment: .bottomTrailing) { fullScreenControl }
            .overlay(alignment: .bottomLeading) { edgeLightControl }
    }

    /// The thin bright-white inset fill-light frame on the windowed preview when the edge light is on
    /// (the overlay draws a much thicker one). Non-hit-testing so it never blocks the tap-to-resize.
    @ViewBuilder private var edgeLightFrame: some View {
        if model.edgeLightOn {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(.white, lineWidth: 6)
                .allowsHitTesting(false)
        }
    }

    /// The ☀ edge-light toggle (bottom-leading, opposite the full-screen control).
    private var edgeLightControl: some View {
        Button { model.toggleEdgeLight() } label: {
            Image(systemName: model.edgeLightOn ? "sun.max.fill" : "sun.max")
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(DS.Space.xs)
        .help("Edge light")
    }

    private var collapseControl: some View {
        Button { model.dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(DS.Space.xs)
        .help("Collapse Mirror")
    }

    /// Blows the self-view up to a full-display overlay (spec decision #2). Bottom-trailing so it
    /// doesn't collide with the × (top-trailing) or the source picker (top-leading).
    private var fullScreenControl: some View {
        Button { model.toggleFullScreen() } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(DS.Space.xs)
        .help("Full screen")
    }

    @ViewBuilder private var sourcePicker: some View {
        if model.devices.count > 1 {
            Menu {
                Button("Default") { model.selectDevice(nil) }
                ForEach(model.devices) { device in
                    Button(device.name) { model.selectDevice(device.id) }
                }
            } label: {
                Image(systemName: "camera.rotate")
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .padding(DS.Space.xs)
            .help("Camera source")
        }
    }
}

private extension View {
    /// Subtle rounded glass surface so the collapsed button and prompts read as one slim strip,
    /// matching the tiles' surface (white 6% fill + hairline border).
    func glassStrip() -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return padding(DS.Space.sm)
            .background(shape.fill(Color.white.opacity(0.06)))
            .overlay(shape.strokeBorder(DS.Palette.hairline, lineWidth: 1))
    }
}

/// Hosts the camera's `AVCaptureVideoPreviewLayer` in a layer-backed `NSView`, keeping the
/// layer's frame pinned to the view's bounds so it resizes correctly between small and expanded.
/// Reused by the full-screen overlay (`MirrorOverlayView`), hence internal.
struct CameraPreview: NSViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> NSView {
        let view = PreviewHostView()
        view.wantsLayer = true
        view.previewLayer = layer
        view.layer?.addSublayer(layer)
        layer.frame = view.bounds
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        layer.frame = nsView.bounds
    }

    /// Re-pins the preview layer on every layout pass so it tracks live size changes.
    private final class PreviewHostView: NSView {
        weak var previewLayer: AVCaptureVideoPreviewLayer?
        override func layout() {
            super.layout()
            previewLayer?.frame = bounds
        }
    }
}
