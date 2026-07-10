import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let frameScript = UTType(exportedAs: "com.framescript.project")
}

struct FrameScriptFile: Codable {
    var fileVersion: Int
    var project: ProjectDTO

    init(project: FrameProject) {
        fileVersion = 2
        self.project = ProjectDTO(project: project)
    }

    func makeProject() -> FrameProject {
        project.makeProject()
    }
}

// DTOs keep the public file format stable while SwiftData models stay free to
// evolve with app-only relationships and derived state.
struct ProjectDTO: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var templateID: UUID?
    var scenes: [SceneDTO]
    var settingsOverride: ProjectSettingsOverride?
    var exportPresets: [ExportPreset]

    init(project: FrameProject) {
        id = project.id
        title = project.title
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        templateID = project.templateID
        scenes = project.scenes.sortedByOrder.map(SceneDTO.init)
        settingsOverride = project.settingsOverride
        exportPresets = project.exportPresets
    }

    func makeProject() -> FrameProject {
        FrameProject(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            templateID: templateID,
            scenes: scenes.map { $0.makeScene() },
            settingsOverride: settingsOverride,
            exportPresets: exportPresets
        )
    }
}

struct SceneDTO: Codable {
    var id: UUID
    var order: Int
    var sectionType: SectionType
    var title: String
    var scriptText: String
    var notes: String
    var estimatedDuration: TimeInterval
    var textSegments: [TextSegmentDTO]
    var aiComments: [AICommentDTO]
    var bRollItems: [BRollItemDTO]
    var editingItems: [EditingItemDTO]

    init(scene: Scene) {
        id = scene.id
        order = scene.order
        sectionType = scene.sectionType
        title = scene.title
        scriptText = scene.scriptText
        notes = scene.notes
        estimatedDuration = scene.estimatedDuration
        textSegments = scene.textSegments.sortedByOrder.map(TextSegmentDTO.init)
        aiComments = scene.aiComments.map(AICommentDTO.init)
        bRollItems = scene.bRollItems.map(BRollItemDTO.init)
        editingItems = scene.editingItems.map(EditingItemDTO.init)
    }

    func makeScene() -> Scene {
        Scene(
            id: id,
            order: order,
            sectionType: sectionType,
            title: title,
            scriptText: scriptText,
            notes: notes,
            estimatedDuration: estimatedDuration,
            textSegments: textSegments.map { $0.makeTextSegment() },
            aiComments: aiComments.map { $0.makeAIComment() },
            bRollItems: bRollItems.map { $0.makeBRollItem() },
            editingItems: editingItems.map { $0.makeEditingItem() }
        )
    }
}

struct TextSegmentDTO: Codable {
    var id: UUID
    var sceneID: UUID
    var order: Int
    var sourceText: String
    var segmentType: SegmentType
    var timingEstimate: TimeInterval

    init(segment: TextSegment) {
        id = segment.id
        sceneID = segment.sceneID
        order = segment.order
        sourceText = segment.sourceText
        segmentType = segment.segmentType
        timingEstimate = segment.timingEstimate
    }

    func makeTextSegment() -> TextSegment {
        TextSegment(
            id: id,
            sceneID: sceneID,
            order: order,
            sourceText: sourceText,
            segmentType: segmentType,
            timingEstimate: timingEstimate
        )
    }
}

struct BRollItemDTO: Codable {
    var id: UUID
    var linkedSegmentID: UUID?
    var sourceType: BRollSourceType
    var descriptionText: String
    var notes: String

    init(item: BRollItem) {
        id = item.id
        linkedSegmentID = item.linkedSegmentID
        sourceType = item.sourceType
        descriptionText = item.descriptionText
        notes = item.notes
    }

    func makeBRollItem() -> BRollItem {
        BRollItem(
            id: id,
            linkedSegmentID: linkedSegmentID,
            templateType: "",
            sourceType: sourceType,
            descriptionText: descriptionText,
            notes: notes
        )
    }

    enum CodingKeys: String, CodingKey { case id, linkedSegmentID, sourceType, descriptionText, notes }
}

struct EditingItemDTO: Codable {
    var id: UUID
    var linkedSegmentID: UUID?
    var description: String
    var notes: String

    init(item: EditingItem) {
        id = item.id
        linkedSegmentID = item.linkedSegmentID
        description = item.cutStyle
        notes = item.notes
    }

    enum CodingKeys: String, CodingKey { case id, linkedSegmentID, description, cutStyle, notes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        linkedSegmentID = try container.decodeIfPresent(UUID.self, forKey: .linkedSegmentID)
        description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .cutStyle)
            ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(linkedSegmentID, forKey: .linkedSegmentID)
        try container.encode(description, forKey: .description)
        try container.encode(notes, forKey: .notes)
    }

    func makeEditingItem() -> EditingItem {
        EditingItem(
            id: id,
            linkedSegmentID: linkedSegmentID,
            templateType: "",
            cutStyle: description,
            transition: "",
            subtitleStyle: "",
            notes: notes
        )
    }
}

struct AICommentDTO: Codable {
    var id: UUID
    var sceneID: UUID?
    var segmentID: UUID?
    var type: String
    var severity: AICommentSeverity
    var message: String
    var suggestion: String
    var status: AICommentStatus

    init(comment: AIComment) {
        id = comment.id
        sceneID = comment.sceneID
        segmentID = comment.segmentID
        type = comment.type
        severity = comment.severity
        message = comment.message
        suggestion = comment.suggestion
        status = comment.status
    }

    func makeAIComment() -> AIComment {
        AIComment(
            id: id,
            sceneID: sceneID,
            segmentID: segmentID,
            type: type,
            severity: severity,
            message: message,
            suggestion: suggestion,
            status: status
        )
    }
}

enum FrameScriptFileStore {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func write(project: FrameProject, to url: URL) throws {
        let data = try encoder.encode(FrameScriptFile(project: project))
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> FrameProject {
        let data = try Data(contentsOf: url)
        return try decoder.decode(FrameScriptFile.self, from: data).makeProject()
    }
}
