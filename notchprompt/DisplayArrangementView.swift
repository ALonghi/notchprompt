//
//  DisplayArrangementView.swift
//  notchprompt
//

import SwiftUI

/// A miniature of the display arrangement in System Settings. Clicking a
/// display puts the teleprompter on it.
struct DisplayArrangementView: View {
    let displays: [DisplayInfo]
    let overlayDisplayID: CGDirectDisplayID?
    /// Overlay size in points, to draw it to scale on the chosen display.
    let overlaySize: CGSize
    let onSelect: (DisplayInfo) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = ArrangementLayout(displays: displays, size: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(displays) { display in
                    let rect = layout.rect(for: display)
                    DisplayTile(
                        display: display,
                        size: rect.size,
                        isSelected: display.id == overlayDisplayID,
                        overlaySize: overlaySize
                    ) {
                        onSelect(display)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display arrangement")
    }
}

private struct ArrangementLayout {
    private let bounds: CGRect
    private let scale: CGFloat
    private let origin: CGPoint

    init(displays: [DisplayInfo], size: CGSize, inset: CGFloat = 4) {
        let union = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull, union.width > 0, union.height > 0 else {
            bounds = .zero
            scale = 0
            origin = .zero
            return
        }
        let available = CGSize(width: max(size.width - inset * 2, 1), height: max(size.height - inset * 2, 1))
        let scale = min(available.width / union.width, available.height / union.height)
        bounds = union
        self.scale = scale
        origin = CGPoint(
            x: (size.width - union.width * scale) / 2,
            y: (size.height - union.height * scale) / 2
        )
    }

    /// The display's tile in view coordinates. Screen frames have a bottom-left
    /// origin, so y is flipped.
    func rect(for display: DisplayInfo) -> CGRect {
        let frame = display.frame
        return CGRect(
            x: origin.x + (frame.minX - bounds.minX) * scale,
            y: origin.y + (bounds.maxY - frame.maxY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        // Arranged displays touch; leave a gap between tiles.
        .insetBy(dx: 1.5, dy: 1.5)
    }
}

private struct DisplayTile: View {
    let display: DisplayInfo
    let size: CGSize
    let isSelected: Bool
    let overlaySize: CGSize
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fill)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(stroke, lineWidth: isSelected ? 2 : 1)

                if isSelected {
                    overlayMarker
                }

                label
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isSelected ? "The teleprompter is on \(display.name)" : "Show the teleprompter on \(display.name)")
        .accessibilityLabel(display.name)
        .accessibilityHint(isSelected ? "The teleprompter is on this display" : "Moves the teleprompter to this display")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.primary.opacity(isHovering ? 0.12 : 0.06)
    }

    private var stroke: Color {
        if isSelected { return Color.accentColor }
        return Color.primary.opacity(isHovering ? 0.4 : 0.2)
    }

    /// The overlay, to scale, hanging from the top edge.
    private var overlayMarker: some View {
        let width = min(max(size.width * overlaySize.width / max(display.frame.width, 1), 10), size.width * 0.8)
        let height = min(max(size.height * overlaySize.height / max(display.frame.height, 1), 3), 10)
        return UnevenRoundedRectangle(bottomLeadingRadius: 2, bottomTrailingRadius: 2, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: width, height: height)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var label: some View {
        VStack(spacing: 2) {
            if size.height >= 46 && size.width >= 40 {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
            }
            if size.height >= 20 {
                Text(display.name)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .padding(.top, isSelected ? 6 : 0)
    }
}
