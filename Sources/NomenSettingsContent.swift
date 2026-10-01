import SwiftUI

struct NomenSettingsContent: View {
    @ObservedObject var engine: NomenEngine
    /// Read when the window opens and again each time it becomes key, because Apple
    /// Intelligence can be turned on or off in System Settings while this window is open.
    @State private var modelState = Namer.modelState

    var body: some View {
        Section(L10n.string("settings.naming", defaultValue: "Naming")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.string("settings.namer", defaultValue: "Names come from"))
                    Spacer()
                    Text(modelSummary).foregroundStyle(.secondary)
                }
                Text(modelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.string("settings.keep_date", defaultValue: "Keep the date in the name"))
                    Spacer()
                    Toggle(L10n.string("settings.keep_date", defaultValue: "Keep the date in the name"),
                           isOn: $engine.keepDate)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                Text(L10n.string("settings.keep_date_caption",
                                 defaultValue: "Adds the time the screenshot was taken, as macOS does: \u{201C}stripe-dashboard 2026-10-01 at 14.04.21.png\u{201D}."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section(L10n.string("settings.screenshots", defaultValue: "Screenshots")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.string("settings.folder", defaultValue: "Folder"))
                    Spacer()
                    Text(displayPath(engine.folder))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L10n.string("settings.show", defaultValue: "Show")) {
                        NSWorkspace.shared.open(engine.folder)
                    }
                }
                Text(L10n.string("settings.folder_caption",
                                 defaultValue: "Nomen follows the folder macOS saves screenshots to. Change it in the Screenshot app: press shift, command and 5, then choose Options. Only screenshots taken while Nomen is running are renamed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            modelState = Namer.modelState
        }
    }

    private var modelSummary: String {
        switch modelState {
        case .imageAndText:
            return L10n.string("settings.model_image", defaultValue: "Apple Intelligence")
        case .textOnly:
            return L10n.string("settings.model_text", defaultValue: "Apple Intelligence (text)")
        case .unavailable:
            return L10n.string("settings.model_rules", defaultValue: "Simple rules")
        }
    }

    private var modelCaption: String {
        switch modelState {
        case .imageAndText:
            return L10n.string("settings.model_image_caption",
                               defaultValue: "The on-device model looks at each screenshot and the text in it. Nothing leaves your Mac.")
        case .textOnly:
            return L10n.string("settings.model_text_caption",
                               defaultValue: "The on-device model reads the text in each screenshot. Nothing leaves your Mac.")
        case .unavailable(let reason):
            return L10n.format("settings.model_rules_caption",
                               defaultValue: "Apple Intelligence is not available (%@), so names are made from the app and the first words in the screenshot.",
                               reason)
        }
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
