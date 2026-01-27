import AppKit
import Foundation

struct ScreenInfo {
    let screen: NSScreen
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let isMain: Bool
}

struct ScreenDetector {
    static func getAllScreens() -> [ScreenInfo] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = screen.displayID else { return nil }
            return ScreenInfo(
                screen: screen,
                displayID: displayID,
                frame: screen.frame,
                isMain: screen == NSScreen.main
            )
        }
    }

    static func getMainScreen() -> ScreenInfo? {
        guard let mainScreen = NSScreen.main,
              let displayID = mainScreen.displayID else {
            return nil
        }
        return ScreenInfo(
            screen: mainScreen,
            displayID: displayID,
            frame: mainScreen.frame,
            isMain: true
        )
    }

    static func getScreen(at point: CGPoint) -> ScreenInfo? {
        for screen in NSScreen.screens {
            if screen.frame.contains(point) {
                guard let displayID = screen.displayID else { continue }
                return ScreenInfo(
                    screen: screen,
                    displayID: displayID,
                    frame: screen.frame,
                    isMain: screen == NSScreen.main
                )
            }
        }
        return nil
    }
}
