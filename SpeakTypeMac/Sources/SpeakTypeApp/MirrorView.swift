import SwiftUI
import AppKit
import AVFoundation
import SpeakTypeCore

/// The Mirror strip that rides at the top of the Shelf: a slim "Mirror" button when collapsed,
/// a live mirrored self-view (small or expanded) when open. Tapping the preview toggles size;
/// a top-right × collapses it (camera off). A source picker appears only when more than one
/// camera exists. If permission is denied, a compact inline prompt links to System Settings.
struct MirrorView: View {
    @ObservedObject var model: MirrorModel

    var body: some View {
        if model.permissionDenied {
            permissionPrompt
        } else {
            switch model.state {
            case .collapsed: collapsedButton
            case .small:     preview(height: 72)
            case .expanded:  preview(height: 150)
            }
        }
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
    }

    /// The live preview at the given height: tap toggles small⇄expanded, with overlaid collapse
    /// control and (when >1 camera) source picker.
    private func preview(height: CGFloat) -> some View {
        CameraPreview(layer: model.previewLayer)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { model.tap() }
            .overlay(alignment: .topTrailing) { collapseControl }
            .overlay(alignment: .topLeading) { sourcePicker }
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

/// Hosts the camera's `AVCaptureVideoPreviewLayer` in a layer-backed `NSView`, keeping the
/// layer's frame pinned to the view's bounds so it resizes correctly between small and expanded.
private struct CameraPreview: NSViewRepresentable {
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
