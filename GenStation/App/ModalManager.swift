import SwiftUI
import GenStationCore

struct ModalManager<Content: View>: ViewModifier {
    @Binding var presentedModal: PresentedModal?
    let content: Content
    @EnvironmentObject var appState: AppState
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    func body(content: Self.Content) -> some View {
        content
            .modifier(VideoReviewModifier(queue: appState.jobQueue, enabled: presentedModal == nil))
            .sheet(item: Binding<PresentedModal?>(
                get: { presentedModal?.isSheetModal == true ? presentedModal : nil },
                set: { presentedModal = $0 }
            )) { modal in
                modalContent(for: modal)
                    .modifier(VideoReviewModifier(queue: appState.jobQueue))
                    .environmentObject(appState)
                    .presentationDetents(presentationDetents(for: modal))
                    .presentationDragIndicator(.visible)
            }
            #if os(iOS)
            .fullScreenCover(item: Binding<PresentedModal?>(
                get: { presentedModal?.isFullCoverModal == true ? presentedModal : nil },
                set: { presentedModal = $0 }
            )) { modal in
                modalContent(for: modal)
                    .modifier(VideoReviewModifier(queue: appState.jobQueue))
                    .environmentObject(appState)
            }
            #endif
            #if os(macOS)
            .onReceive(appState.$presentedModal) { newModal in
                if let modal = newModal, modal.isFullCoverModal {
                    handleMacFullModal(modal)
                    appState.presentedModal = nil
                }
            }
            #endif
    }

    private func presentationDetents(for modal: PresentedModal) -> Set<PresentationDetent> {
        switch modal {
        case .responseSheet:
            return [.large]
        case .deleteConfirmation:
            return [.height(260)]
        default:
            return [.medium, .large]
        }
    }

    @ViewBuilder
    private func modalContent(for modal: PresentedModal) -> some View {
        switch modal {
        case .responseSheet:
            PopOutView()

        case .jobs:
            JobsPanelView()

        case .namedWorkflow(let workflowID, let assetID):
            WorkflowNamedRunView(initialWorkflowID: workflowID, initialAssetID: assetID)

        case .fullHistoryItem(let id):
            FullHistoryItemView(initialId: id)

        case .markupSlot(let slotId):
            NavigationStack {
                MarkupWindowView(slotId: slotId)
            }

        case .history:
            EmptyView()

        case .textEditor(_):
            EmptyView()

        case .advancedSettings:
            AdvancedAIMLSettingsView(
                model: appState.currentAIMLModel,
                params: $appState.settings.aimlAdvancedParams,
                isVideo: appState.settings.isVideoMode
            )

        case .help(let mode):
            HelpView(mode: mode)

        case .comfyUIWarning:
            ComfyUIResponsibilityWarning { presentedModal = nil }

        case .mandatory:
            MandatoryFirstLaunchView {
                appState.settings.hasCompletedMandatory = true
                if !appState.settings.hasSeenAPIKeySetup {
                    presentedModal = .apiKeySetup  // Direct replace – smooth transition to API key setup
                } else if !appState.settings.hasSeenPrettyOnboarding {
                    presentedModal = .onboarding
                } else {
                    presentedModal = nil  // Clean final dismiss
                }
            }
            .interactiveDismissDisabled()

        case .apiKeySetup:
            #if os(iOS)
            NavigationStack {
                APIKeySetupWizard {
                    appState.settings.hasSeenAPIKeySetup = true
                    appState.settings.hasSeenPrettyOnboarding = true
                    presentedModal = nil
                }
                .environmentObject(appState)
                .toolbar(.hidden, for: .navigationBar)
                .keyboardDoneButton()
            }
            .interactiveDismissDisabled()
            #else
            APIKeySetupWizard {
                appState.settings.hasSeenAPIKeySetup = true
                appState.settings.hasSeenPrettyOnboarding = true
                presentedModal = nil
            }
            .environmentObject(appState)
            .interactiveDismissDisabled()
            #endif

        case .onboarding:
            OnboardingView(onDismiss: {
                // Show output folder setup if not seen yet
                if !appState.settings.hasSeenOutputFolderSetup {
                    appState.settings.hasSeenOutputFolderSetup = true
                    presentedModal = .outputFolderSetup
                } else {
                    presentedModal = nil
                }
            })

        case .outputFolderSetup:
            OutputFolderSetupView(onDismiss: { presentedModal = nil })

        case .contentFilterBlocked(let entries):
            ContentFilterBlockedView(offendingEntries: entries) { presentedModal = nil }

        case .deleteConfirmation(let info):
            DeleteConfirmationView(
                title: info.title,
                message: info.message,
                hasDeletableFiles: info.hasDeletableFiles,
                deleteAction: info.onConfirm,
                cancelAction: { presentedModal = nil }
            )

        case .imageDescription(let description):
            ImageDescriptionSheet(
                description: description,
                onUseAsPrompt: {
                    appState.prompt = description
                    presentedModal = nil
                },
                onCopy: {
                    PlatformPasteboard.writeString(description)
                },
                onDismiss: {
                    presentedModal = nil
                }
            )

        }
    }

    #if os(macOS)
    private func handleMacFullModal(_ modal: PresentedModal) {
        switch modal {
        case .responseSheet:
            openWindow(id: "response-window")
        case .fullHistoryItem(let id):
            #if swift(>=5.7)
            openWindow(id: "history-viewer", value: id)
            #else
            // Fallback stub
            #endif
        case .markupSlot(let slotId):
            openWindow(value: slotId)
        case .textEditor(_):
            break
        case .help(let mode):
            openWindow(id: "help-window", value: mode)
        default:
            break
        }
    }
    #endif
}

extension View {
    func modalManager(presentedModal: Binding<PresentedModal?>) -> some View {
        modifier(ModalManager(presentedModal: presentedModal, content: self))
    }
}
