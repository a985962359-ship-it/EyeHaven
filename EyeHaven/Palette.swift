import SwiftUI
import UIKit

enum Palette {
    static let mist = Color(red: 0.93, green: 0.95, blue: 0.92)
    static let foam = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let pine = Color(red: 0.18, green: 0.35, blue: 0.32)
    static let moss = Color(red: 0.33, green: 0.55, blue: 0.46)
    static let sage = Color(red: 0.62, green: 0.75, blue: 0.66)
    static let dusk = Color(red: 0.12, green: 0.18, blue: 0.17)
    static let gold = Color(red: 0.82, green: 0.68, blue: 0.42)
}

enum HavenLayout {
    /// 分屏很窄时按手机排版，避免 iPad 小窗仍用大圆环、大字号挤爆。
    private static let padLayoutMinWidth: CGFloat = 560

    static var isPad: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        return activeWindowWidth >= padLayoutMinWidth
    }

    /// Keep paragraphs readable on iPad instead of stretching edge to edge.
    static var pageMaxWidth: CGFloat { isPad ? 640 : .infinity }

    static var timerRingSize: CGFloat { isPad ? 260 : 200 }
    static var timerRingFont: CGFloat { isPad ? 58 : 48 }

    static var restTimerFont: CGFloat { isPad ? 80 : 56 }
    static var restTimerHeight: CGFloat { isPad ? 108 : 80 }

    static var distanceRingSize: CGFloat { isPad ? 300 : 240 }

    private static var activeWindowWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let width = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.bounds.width {
            return width
        }
        if let width = scenes.first?.windows.first?.bounds.width {
            return width
        }
        return UIScreen.main.bounds.width
    }
}
