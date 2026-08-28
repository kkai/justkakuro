#if os(iOS)
import Foundation
import Testing
import UIKit
@testable import Kakuro

/// The edge swipe used to be able to pop a puzzle mid-solve. These exercise the
/// mechanism directly, against a real `UINavigationController`.
///
/// They exist because the obvious end-to-end check does not work: fb-idb's
/// synthetic swipe cannot drive UIKit's interactive pop recogniser at all, so
/// "the board survived an edge swipe" is true whether or not the fix is
/// present. A control run on a screen that was never meant to be protected
/// failed to pop either, which is what gave that away.
@Suite("Swipe back")
@MainActor
struct SwipeBackTests {

    private func hosted() -> (UINavigationController, SwipeBackDisabler.Controller) {
        let controller = SwipeBackDisabler.Controller()
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.pushViewController(controller, animated: false)
        return (nav, controller)
    }

    @Test func theGestureIsOffWhileABoardIsOnScreen() {
        let (nav, controller) = hosted()
        nav.interactivePopGestureRecognizer?.isEnabled = true
        controller.viewWillAppear(false)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == false)
    }

    /// The half that matters. The recogniser belongs to the navigation
    /// controller, not to the screen, so failing to put it back would disable
    /// swipe-back for the whole app for the rest of the session.
    @Test func theGestureComesBackOnTheWayOut() {
        let (nav, controller) = hosted()
        nav.interactivePopGestureRecognizer?.isEnabled = true
        controller.viewWillAppear(false)
        controller.viewWillDisappear(false)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == true)
    }

    /// Restores whatever the value actually was, rather than assuming it was
    /// on. Two board screens in a row must not leave the gesture enabled when
    /// the inner one is popped back to the outer one.
    @Test func restoringPutsBackThePreviousValueNotJustTrue() {
        let (nav, controller) = hosted()
        nav.interactivePopGestureRecognizer?.isEnabled = false
        controller.viewWillAppear(false)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == false)
        controller.viewWillDisappear(false)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == false,
                "it was already off on the way in, so it must stay off on the way out")
    }

    /// Disappearing without ever having appeared must not touch anything.
    @Test func aDisappearWithoutAnAppearChangesNothing() {
        let (nav, controller) = hosted()
        nav.interactivePopGestureRecognizer?.isEnabled = true
        controller.viewWillDisappear(false)
        #expect(nav.interactivePopGestureRecognizer?.isEnabled == true)
    }

    /// Every screen holding live puzzle state has to carry the modifier, or
    /// the bug comes back on whichever one was missed.
    @Test func everyBoardScreenDisablesIt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        for (file, screens) in [("Kakuro/Game/GameView.swift", 1),
                                ("Kakuro/Teaching/TutorialView.swift", 1),
                                ("Kakuro/Teaching/PracticeView.swift", 1)] {
            let source = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            let count = source.components(separatedBy: ".swipeBackDisabled()").count - 1
            #expect(count == screens,
                    "\(file) should disable the swipe on \(screens) screen(s), found \(count)")
        }
    }
}
#endif
