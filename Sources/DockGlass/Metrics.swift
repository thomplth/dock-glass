import SwiftUI

extension DockGlass {
    /// Switcher geometry measured from the native macOS 27 Cmd-Tab switcher at its standard
    /// 102pt icon size. Other icon sizes scale every length proportionally, which is an
    /// assumption: only the standard size was measured.
    public struct Metrics: Sendable, Equatable {
        /// Visible icon artwork size.
        public var iconSize: CGFloat

        public init(iconSize: CGFloat = 102) {
            self.iconSize = iconSize
        }

        public static let standard = Metrics()

        var scale: CGFloat { iconSize / 102 }

        /// Distance between the leading edges of neighbouring icons.
        public var iconPitch: CGFloat { 134 * scale }
        public var iconSpacing: CGFloat { iconPitch - iconSize }
        public var horizontalPadding: CGFloat { 37.5 * scale }
        public var topPadding: CGFloat { 35 * scale }
        public var plateHeight: CGFloat { 176 * scale }
        /// Continuous (squircle) corner radius of the plate.
        public var plateCornerRadius: CGFloat { 57.5 * scale }

        /// App icon bitmaps carry a transparent inset around their artwork; drawing the full
        /// canvas at this size makes the artwork exactly `iconSize`.
        public var iconCanvasSize: CGFloat { iconSize * 128 / 102 }
        /// Where native places the icon canvas relative to the centre of its slot.
        public var iconCanvasOffset: CGSize { CGSize(width: 0.5 * scale, height: 2 * scale) }

        /// Selection highlight inset around the icon artwork, on every side.
        public var selectionPadding: CGFloat { 9 * scale }
        /// Continuous corner radius of the selection highlight: the icon's own corner radius plus
        /// the padding, so the two corners stay concentric.
        public var selectionCornerRadius: CGFloat { 33 * scale }
        public var labelFontSize: CGFloat { DockGlass.Label.standardFontSize * scale }
        /// Distance from the icon slot's bottom edge to the label's bottom edge.
        public var labelOffset: CGFloat { 31 * scale }

        /// The plate's outline, for `.dockGlass(in:)` behind content laid out some other way.
        public var plateShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous)
        }

        /// Total plate width for a given number of icons.
        public func plateWidth(iconCount: Int) -> CGFloat {
            guard iconCount > 0 else { return horizontalPadding * 2 }
            return CGFloat(iconCount) * iconPitch - iconSpacing + horizontalPadding * 2
        }
    }
}
