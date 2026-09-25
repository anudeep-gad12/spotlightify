import AppKit
import Carbon
import SwiftUI

private final class SearchPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SearchPanelController: NSWindowController, NSWindowDelegate {
    private let environment: AppEnvironment
    private var localEventMonitor: Any?
    private var previousFrontmostApplication: NSRunningApplication?
    private var shouldRestorePreviousApplication = false

    var isVisible: Bool {
        window?.isVisible == true
    }

    init(environment: AppEnvironment) {
        self.environment = environment

        let panel = SearchPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SearchPanelLayout.windowWidth,
                height: SearchPanelLayout.windowHeight
            ),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.appearance = environment.appearanceStore.preference.appKitAppearance
        // The AppKit window shadow would trace the transparent square bounds.
        panel.hasShadow = false
        panel.delegate = nil

        let rootView = SearchPanelView(
            viewModel: environment.searchViewModel,
            appearanceStore: environment.appearanceStore,
            onAppearanceChanged: { [weak environment] preference in
                environment?.setAppearance(preference)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        panel.contentViewController = hostingController

        super.init(window: panel)

        panel.delegate = self
        installLocalMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        AppLogger.shared.log("toggle requested visible=\(isVisible)", category: "panel")
        isVisible ? close() : show(capturePreviousApplication: true)
    }

    func show(capturePreviousApplication: Bool = false) {
        guard let window else { return }
        AppLogger.shared.log("show begin", category: "panel")
        if capturePreviousApplication {
            captureFrontmostApplicationForRestoration()
        } else {
            shouldRestorePreviousApplication = false
            previousFrontmostApplication = nil
        }
        position(window: window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        environment.searchViewModel.requestSearchFocus()
        AppLogger.shared.log("show end", category: "panel")
    }

    override func close() {
        AppLogger.shared.log("close begin", category: "panel")
        super.close()
        window?.orderOut(nil)
        restorePreviousApplicationIfNeeded()
        AppLogger.shared.log("close end", category: "panel")
    }

    func focusSearchField() {
        environment.searchViewModel.requestSearchFocus()
    }

    func applyAppearance(_ preference: AppearancePreference) {
        window?.appearance = preference.appKitAppearance
        window?.contentView?.needsDisplay = true
    }

    func windowDidResignKey(_ notification: Notification) {
        if environment.authManager.isInteractiveAuthInProgress {
            AppLogger.shared.log("windowDidResignKey ignored during auth", category: "panel")
            return
        }
        if environment.isPlaybackRequestInProgress {
            AppLogger.shared.log("windowDidResignKey ignored during playback request", category: "panel")
            return
        }
        AppLogger.shared.log("windowDidResignKey", category: "panel")
        close()
    }

    private func installLocalMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            if let command = self.terminalEditingCommand(for: event),
               let fieldEditor = self.window?.firstResponder as? NSTextView,
               fieldEditor.isFieldEditor,
               fieldEditor.isEditable {
                fieldEditor.doCommand(by: command)
                return nil
            }

            switch Int(event.keyCode) {
            case kVK_Escape:
                self.environment.closePanel()
                return nil
            case kVK_Tab:
                guard self.environment.searchViewModel.canSwitchModes else { return event }
                self.environment.searchViewModel.cycleMode(backwards: event.modifierFlags.contains(.shift))
                return nil
            case kVK_UpArrow:
                if self.environment.searchViewModel.canHandleSelectionMovement {
                    self.environment.searchViewModel.moveSelection(by: -1)
                    return nil
                }
                return event
            case kVK_DownArrow:
                if self.environment.searchViewModel.canHandleSelectionMovement {
                    self.environment.searchViewModel.moveSelection(by: 1)
                    return nil
                }
                return event
            case kVK_RightArrow:
                if self.environment.searchViewModel.canNavigateIntoAlbum {
                    self.environment.searchViewModel.navigateIntoAlbum()
                    return nil
                }
                return event
            case kVK_LeftArrow:
                if self.environment.searchViewModel.canNavigateBackFromAlbum {
                    self.environment.searchViewModel.navigateBackFromAlbum()
                    return nil
                }
                return event
            case kVK_Return:
                if self.environment.searchViewModel.canMoveSelection {
                    if event.modifierFlags.contains(.command) {
                        self.environment.searchViewModel.queueSelected()
                    } else {
                        self.environment.searchViewModel.playSelected()
                    }
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func terminalEditingCommand(for event: NSEvent) -> Selector? {
        let shortcutModifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if shortcutModifiers == .option {
            switch Int(event.keyCode) {
            case kVK_ANSI_B:
                return #selector(NSResponder.moveWordBackward(_:))
            case kVK_ANSI_F:
                return #selector(NSResponder.moveWordForward(_:))
            default:
                return nil
            }
        }
        guard shortcutModifiers == .control else { return nil }

        switch Int(event.keyCode) {
        case kVK_ANSI_A:
            return #selector(NSResponder.moveToBeginningOfLine(_:))
        case kVK_ANSI_E:
            return #selector(NSResponder.moveToEndOfLine(_:))
        case kVK_ANSI_B:
            return #selector(NSResponder.moveBackward(_:))
        case kVK_ANSI_F:
            return #selector(NSResponder.moveForward(_:))
        case kVK_ANSI_W:
            return #selector(NSResponder.deleteWordBackward(_:))
        case kVK_ANSI_U:
            return #selector(NSResponder.deleteToBeginningOfLine(_:))
        case kVK_ANSI_K:
            return #selector(NSResponder.deleteToEndOfLine(_:))
        case kVK_ANSI_D:
            return #selector(NSResponder.deleteForward(_:))
        case kVK_ANSI_H:
            return #selector(NSResponder.deleteBackward(_:))
        case kVK_ANSI_T:
            return #selector(NSResponder.transpose(_:))
        case kVK_ANSI_Y:
            return #selector(NSResponder.yank(_:))
        default:
            return nil
        }
    }

    private func position(window: NSWindow) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let originX = screenFrame.midX - window.frame.width / 2
        // Keep the visible card's top edge 80pt below the screen top.
        let originY = screenFrame.maxY - window.frame.height - (80 - SearchPanelLayout.windowInset)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func captureFrontmostApplicationForRestoration() {
        let ownBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.bundleIdentifier != ownBundleID {
            previousFrontmostApplication = frontmost
            shouldRestorePreviousApplication = true
            AppLogger.shared.log("captured previous app bundle=\(frontmost.bundleIdentifier ?? "unknown")", category: "panel")
        } else {
            previousFrontmostApplication = nil
            shouldRestorePreviousApplication = false
        }
    }

    private func restorePreviousApplicationIfNeeded() {
        guard shouldRestorePreviousApplication else { return }
        guard let previousFrontmostApplication else {
            shouldRestorePreviousApplication = false
            return
        }

        let appToRestore = previousFrontmostApplication
        shouldRestorePreviousApplication = false
        self.previousFrontmostApplication = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let ownBundleID = Bundle.main.bundleIdentifier
            let currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if let currentFrontmostBundleID, currentFrontmostBundleID != ownBundleID {
                AppLogger.shared.log("skipped restore because another app is already frontmost", category: "panel")
                return
            }

            let restored = appToRestore.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            AppLogger.shared.log("restored previous app bundle=\(appToRestore.bundleIdentifier ?? "unknown") success=\(restored)", category: "panel")
        }
    }
}
