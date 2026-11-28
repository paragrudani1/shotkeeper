import ShotkeeperCore
import SwiftUI

/// Settings › General, the rows under "Move into the organized folder" (wave 2 ticket 04, design §4): the "Sort into
/// subfolders" menu picker and, when a rule is chosen, the example path with its note (or why the organized folder
/// can't take subfolders) and the "left alone" line. The caller shows these only when an organized folder is set and
/// moving is on. Words come from core `SubfolderSettingsText`. Ticket 05 adds "Sort Existing Screenshots…" after the
/// "left alone" line.
struct SubfolderSettingsRows: View {
    @Binding var settings: AppSettings
    /// The organized folder's name as Finder shows it.
    let folderName: String
    let folderStatus: OrganizedFolderStatus

    var body: some View {
        Picker(SubfolderSettingsText.pickerTitle, selection: $settings.subfolderRule) {
            ForEach(SubfolderRule.allCases, id: \.self) { rule in
                Text(SubfolderSettingsText.title(for: rule)).tag(rule)
            }
        }
        .pickerStyle(.menu)
        if settings.subfolderRule != .off {
            if let warning = SubfolderSettingsText.warning(folderStatus, folderName: folderName) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .accessibilityHidden(true)
                    Text(warning)
                        .foregroundStyle(Brand.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: \(warning)")
            } else {
                LabeledContent(SubfolderSettingsText.exampleTitle) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(example)
                            .lineLimit(1).truncationMode(.middle)
                            .help(example)
                        if let note = SubfolderSettingsText.note(for: settings.subfolderRule) {
                            Text(note)
                                .font(.system(size: 11))
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .foregroundStyle(Brand.secondaryText)
                }
            }
            Text(SubfolderSettingsText.leftAlone).foregroundStyle(Brand.secondaryText)
        }
    }

    private var example: String {
        SubfolderSettingsText.example(rule: settings.subfolderRule, folderName: folderName,
                                      style: settings.filenameStyle, renameEnabled: settings.renameEnabled,
                                      capturedAt: FilenameStyleExample.date,
                                      timeZone: TimeZone(secondsFromGMT: 0)!) ?? ""
    }
}
