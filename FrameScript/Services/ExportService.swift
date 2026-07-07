import Foundation
import UniformTypeIdentifiers

protocol ExportServicing {
    func render(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String
    func render(project: FrameProject, format: ExportFormat, preferences: ExportPreferences, language: AppLanguage) -> String
}

struct ExportService: ExportServicing {
    func render(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String {
        render(project: project, format: preferences.defaultFormat, preferences: preferences, language: language)
    }

    func render(project: FrameProject, format: ExportFormat, preferences: ExportPreferences, language: AppLanguage) -> String {
        switch format {
        case .plainText:
            renderPlainText(project: project, preferences: preferences, language: language)
        case .markdown:
            renderMarkdown(project: project, preferences: preferences, language: language)
        case .productionOutline:
            renderProductionOutline(project: project, preferences: preferences, language: language)
        case .csv:
            renderCSV(project: project, preferences: preferences, language: language)
        }
    }

    private func renderPlainText(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String {
        project.scenes.sortedByOrder.map { scene in
            var output = ""
            if preferences.includeSectionNames {
                let timestamp = preferences.includeTimestamps ? " [\(DurationEstimator.formatted(scene.estimatedDuration))]" : ""
                output += "\(scene.title)\(timestamp)\n\n"
            }
            output += formattedScript(scene.scriptText, preferences: preferences)

            if preferences.includeBRoll, !scene.bRollItems.isEmpty {
                output += "\n\n\(label("export.label.broll", language: language)):\n"
                for item in scene.bRollItems {
                    output += "- \(label("brollSource.\(item.sourceType.rawValue)", language: language)): \(item.descriptionText)\n"
                }
            }

            if preferences.includeEditingNotes, !scene.editingItems.isEmpty {
                output += "\n\n\(label("export.label.editing", language: language)):\n"
                for item in scene.editingItems {
                    output += "- \(item.cutStyle); \(item.subtitleStyle); \(item.notes)\n"
                }
            }

            if preferences.includeAINotes, !scene.aiComments.isEmpty {
                output += "\n\n\(label("export.label.aiNotes", language: language)):\n"
                for comment in scene.aiComments where comment.status == .new {
                    output += "- \(comment.message)"
                    if !comment.suggestion.isEmpty {
                        output += " \(label("export.label.suggestion", language: language)): \(comment.suggestion)"
                    }
                    output += "\n"
                }
            }
            return output
        }
        .joined(separator: "\n\n")
    }

    private func renderMarkdown(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String {
        var output = "# \(project.title)\n\n"
        for scene in project.scenes.sortedByOrder {
            if preferences.includeSectionNames {
                let timestamp = preferences.includeTimestamps ? " [\(DurationEstimator.formatted(scene.estimatedDuration))]" : ""
                output += "## \(scene.title)\(timestamp)\n\n"
            }
            output += "\(formattedScript(scene.scriptText, preferences: preferences))\n\n"

            if preferences.includeBRoll, !scene.bRollItems.isEmpty {
                output += "### \(label("export.label.broll", language: language))\n"
                for item in scene.bRollItems {
                    output += "- \(label("brollSource.\(item.sourceType.rawValue)", language: language)): \(item.descriptionText)\n"
                }
                output += "\n"
            }

            if preferences.includeEditingNotes, !scene.editingItems.isEmpty {
                output += "### \(label("export.label.editing", language: language))\n"
                for item in scene.editingItems {
                    output += "- \(item.cutStyle); \(item.subtitleStyle); \(item.notes)\n"
                }
                output += "\n"
            }

            if preferences.includeAINotes, !scene.aiComments.isEmpty {
                output += "### \(label("export.label.aiNotes", language: language))\n"
                for comment in scene.aiComments where comment.status == .new {
                    output += "- \(comment.message)"
                    if !comment.suggestion.isEmpty {
                        output += " \(label("export.label.suggestion", language: language)): \(comment.suggestion)"
                    }
                    output += "\n"
                }
                output += "\n"
            }
        }
        return output
    }

    private func renderProductionOutline(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String {
        var output = "# \(project.title)\n\n"
        for (index, scene) in project.scenes.sortedByOrder.enumerated() {
            let sceneTitle = preferences.includeSectionNames ? scene.title : label("export.label.scene", language: language)
            output += "## \(label("export.label.scene", language: language)) \(String(format: "%02d", index + 1)) — \(sceneTitle)\n"
            if preferences.includeTimestamps {
                output += "\(label("export.label.estimatedDuration", language: language)): \(DurationEstimator.formatted(scene.estimatedDuration))\n\n"
            } else {
                output += "\n"
            }

            output += "\(label("export.label.script", language: language).uppercased()):\n"
            output += "\(formattedScript(scene.scriptText, preferences: preferences))\n\n"

            if preferences.includeBRoll, !scene.bRollItems.isEmpty {
                output += "\(label("export.label.broll", language: language).uppercased()):\n"
                for item in scene.bRollItems {
                    output += "- \(label("export.label.source", language: language)): \(label("brollSource.\(item.sourceType.rawValue)", language: language))\n"
                    appendLine(&output, key: "export.label.description", value: item.descriptionText, language: language, indent: "  ")
                    appendLine(&output, key: "export.label.mood", value: item.mood, language: language, indent: "  ")
                    appendLine(&output, key: "export.label.framing", value: item.framing, language: language, indent: "  ")
                    appendLine(&output, key: "export.label.motion", value: item.motion, language: language, indent: "  ")
                    appendLine(&output, key: "export.label.notes", value: item.notes, language: language, indent: "  ")
                }
                output += "\n"
            }

            if preferences.includeEditingNotes, !scene.editingItems.isEmpty {
                output += "\(label("export.label.editing", language: language).uppercased()):\n"
                for item in scene.editingItems {
                    output += "- \(label("export.label.template", language: language)): \(item.templateType)\n"
                    appendLine(&output, key: "editing.cutStyle", value: item.cutStyle, language: language, indent: "  ")
                    appendLine(&output, key: "editing.transition", value: item.transition, language: language, indent: "  ")
                    appendLine(&output, key: "editing.subtitles", value: item.subtitleStyle, language: language, indent: "  ")
                    appendLine(&output, key: "editing.emphasis", value: item.emphasis, language: language, indent: "  ")
                    appendLine(&output, key: "editing.zoom", value: item.zoom, language: language, indent: "  ")
                    appendLine(&output, key: "editing.sfx", value: item.sfx, language: language, indent: "  ")
                    appendLine(&output, key: "editing.musicCue", value: item.musicCue, language: language, indent: "  ")
                    appendLine(&output, key: "editing.graphics", value: item.graphics, language: language, indent: "  ")
                    appendLine(&output, key: "editing.notes", value: item.notes, language: language, indent: "  ")
                }
                output += "\n"
            }

            if preferences.includeAINotes, !scene.aiComments.isEmpty {
                output += "\(label("export.label.aiNotes", language: language).uppercased()):\n"
                for comment in scene.aiComments where comment.status == .new {
                    output += "- \(comment.message)\n"
                    appendLine(&output, key: "export.label.suggestion", value: comment.suggestion, language: language, indent: "  ")
                }
                output += "\n"
            }
        }
        return output
    }

    private func renderCSV(project: FrameProject, preferences: ExportPreferences, language: AppLanguage) -> String {
        var headers = [
            label("export.label.scene", language: language),
            label("export.label.title", language: language),
            label("export.label.duration", language: language),
            label("export.label.script", language: language)
        ]
        if preferences.includeBRoll { headers.append(label("export.label.broll", language: language)) }
        if preferences.includeEditingNotes { headers.append(label("export.label.editing", language: language)) }
        if preferences.includeAINotes { headers.append(label("export.label.aiNotes", language: language)) }
        var rows = [headers.joined(separator: ",")]
        for scene in project.scenes.sortedByOrder {
            let title = preferences.includeSectionNames ? scene.title.replacingOccurrences(of: "\"", with: "\"\"") : ""
            let duration = preferences.includeTimestamps ? "\(Int(scene.estimatedDuration))" : ""
            var columns = [
                "\(scene.order + 1)",
                title,
                duration,
                scene.scriptText
            ]
            if preferences.includeBRoll {
                columns.append(scene.bRollItems.map { "\(label("brollSource.\($0.sourceType.rawValue)", language: language)): \($0.descriptionText)" }.joined(separator: " | "))
            }
            if preferences.includeEditingNotes {
                columns.append(scene.editingItems.map { "\($0.cutStyle); \($0.subtitleStyle); \($0.notes)" }.joined(separator: " | "))
            }
            if preferences.includeAINotes {
                columns.append(scene.aiComments.filter { $0.status == .new }.map(\.message).joined(separator: " | "))
            }
            rows.append(columns.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func formattedScript(_ text: String, preferences: ExportPreferences) -> String {
        preferences.teleprompterFormatting ? text.replacingOccurrences(of: ". ", with: ".\n\n") : text
    }

    private func appendLine(_ output: inout String, key: String, value: String, language: AppLanguage, indent: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        output += "\(indent)\(label(key, language: language)): \(value)\n"
    }

    private func label(_ key: String, language: AppLanguage) -> String {
        L10n.tr(key, language: language)
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

extension ExportFormat {
    var fileExtension: String {
        switch self {
        case .plainText: "txt"
        case .markdown, .productionOutline: "md"
        case .csv: "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .plainText: .plainText
        case .markdown, .productionOutline: UTType(filenameExtension: "md") ?? .plainText
        case .csv: UTType(filenameExtension: "csv") ?? .commaSeparatedText
        }
    }
}
