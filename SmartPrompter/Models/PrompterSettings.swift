import Foundation
import SwiftData
import SwiftUI
import UIKit

@Model
final class PrompterSettings {
    var fontSize: Double
    var scrollSpeed: Double
    var margins: Double
    var mirrorMode: Bool
    var showMarker: Bool
    var smartVoiceScroll: Bool
    var fontColorHex: String
    var backgroundColorHex: String

    init(
        fontSize: Double = 42,
        scrollSpeed: Double = 34,
        margins: Double = 40,
        mirrorMode: Bool = false,
        showMarker: Bool = true,
        smartVoiceScroll: Bool = false,
        fontColorHex: String = "#F8F8F8",
        backgroundColorHex: String = "#050505"
    ) {
        self.fontSize = fontSize
        self.scrollSpeed = scrollSpeed
        self.margins = margins
        self.mirrorMode = mirrorMode
        self.showMarker = showMarker
        self.smartVoiceScroll = smartVoiceScroll
        self.fontColorHex = fontColorHex
        self.backgroundColorHex = backgroundColorHex
    }

    var fontColor: Color {
        get { Color(hex: fontColorHex) }
        set { fontColorHex = newValue.hexString() }
    }

    var backgroundColor: Color {
        get { Color(hex: backgroundColorHex) }
        set { backgroundColorHex = newValue.hexString() }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 3:
            alpha = 255
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        case 6:
            alpha = 255
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        case 8:
            alpha = (value >> 24) & 0xFF
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        default:
            alpha = 255
            red = 248
            green = 248
            blue = 248
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }

    func hexString() -> String {
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#F8F8F8"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
}
