import Foundation

enum SampleData {
    static let templates: [FrameTemplate] = [
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            category: .script,
            name: "Blank",
            builtIn: true,
            structureDefinition: [],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            category: .script,
            name: "Standard YouTube",
            builtIn: true,
            structureDefinition: ["Hook", "Problem", "Why this matters", "Explanation", "Example", "Takeaway", "CTA"],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            category: .script,
            name: "Educational",
            builtIn: true,
            structureDefinition: ["Hook", "Context", "Problem", "Core explanation", "Example", "Summary", "CTA"],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            category: .script,
            name: "Storytelling",
            builtIn: true,
            structureDefinition: ["Setup", "Conflict", "Turning point", "Resolution", "Lesson", "CTA"],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            category: .script,
            name: "Product Review",
            builtIn: true,
            structureDefinition: ["Hook", "Product context", "What works", "What does not", "Verdict", "CTA"],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            category: .script,
            name: "Commentary / Essay",
            builtIn: true,
            structureDefinition: ["Thesis", "Context", "Argument", "Counterpoint", "Implication", "Closing"],
            customFields: []
        ),
        FrameTemplate(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
            category: .script,
            name: "Tutorial",
            builtIn: true,
            structureDefinition: ["Goal", "Requirements", "Step 1", "Step 2", "Common mistake", "Recap"],
            customFields: []
        )
    ]

    static var defaultProject: FrameProject {
        project(named: "Untitled Script", template: templates.first, blankProjectStart: .oneEmptyScene)
    }

    static func project(
        named title: String,
        template: FrameTemplate?,
        blankProjectStart: BlankProjectStart = .oneEmptyScene,
        defaultSceneName: String = "New scene",
        exportPresetName: String = "Editor handoff",
        sceneNameResolver: (String) -> String = { $0 }
    ) -> FrameProject {
        let structure: [String]
        if template?.isBlank == true {
            structure = blankProjectStart == .oneEmptyScene ? [""] : []
        } else {
            structure = template?.structureDefinition ?? ["Hook", "Problem", "Explanation", "Example", "CTA"]
        }
        let scenes = structure.enumerated().map { index, name in
            let sceneID = UUID()
            let title = name.isEmpty ? defaultSceneName : sceneNameResolver(name)
            return Scene(
                id: sceneID,
                order: index,
                sectionType: SectionType(rawValue: name) ?? .custom,
                title: title,
                scriptText: "",
                notes: "",
                textSegments: [
                    TextSegment(sceneID: sceneID, order: 0, sourceText: "", segmentType: .paragraph)
                ]
            )
        }

        return FrameProject(
            title: title,
            templateID: template?.id,
            scenes: scenes,
            exportPresets: [
                ExportPreset(id: UUID(), name: exportPresetName, format: .productionOutline)
            ]
        )
    }

    static func demoProject(language: AppLanguage) -> FrameProject {
        if language == .russian {
            return russianDemoProject
        }
        return englishDemoProject
    }

    private static var englishDemoProject: FrameProject {
        let hookID = UUID()
        let problemID = UUID()
        let explanationID = UUID()
        let hookSegmentID = UUID()
        let problemSegmentID = UUID()
        let explanationSegmentID = UUID()

        return FrameProject(
            id: UUID(),
            title: "Untitled YouTube Script",
            createdAt: Date(),
            updatedAt: Date(),
            templateID: templates.first?.id,
            scenes: [
                Scene(
                    id: hookID,
                    order: 0,
                    sectionType: .hook,
                    title: "Hook",
                    scriptText: "Most creator tools treat a video like a blank page. But a good YouTube video is not one document. It is a script, a visual plan, and an edit rhythm moving together.",
                    notes: "Open with the product thesis, not feature trivia.",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: hookSegmentID, sceneID: hookID, order: 0, sourceText: "Most creator tools treat a video like a blank page.", segmentType: .paragraph, timingEstimate: 4)
                    ],
                    aiComments: [
                        AIComment(
                            id: UUID(),
                            sceneID: hookID,
                            segmentID: hookSegmentID,
                            type: "Hook",
                            severity: .suggestion,
                            message: "The first sentence is clear, but could carry a sharper contrast.",
                            suggestion: "Try naming the pain before the product idea.",
                            status: .new
                        )
                    ],
                    bRollItems: [
                        BRollItem(
                            id: UUID(),
                            linkedSegmentID: hookSegmentID,
                            templateType: "Stock footage",
                            sourceType: .screenRecording,
                            descriptionText: "Quick cuts between a blank document, timeline, and scattered notes.",
                            mood: "calm frustration",
                            framing: "tight screen crop",
                            motion: "slow push-in",
                            duration: 6,
                            notes: "Keep it restrained. No flashy montage.",
                            status: .planned
                        )
                    ],
                    editingItems: [
                        EditingItem(
                            id: UUID(),
                            linkedSegmentID: hookSegmentID,
                            templateType: "Educational YouTube",
                            cutStyle: "Clean jump cuts",
                            transition: "Hard cut",
                            subtitleStyle: "Keyword highlights only",
                            emphasis: "Highlight 'not one document'",
                            zoom: "Subtle punch-in on thesis",
                            sfx: "",
                            musicCue: "Soft bed starts after first sentence",
                            graphics: "Three labels: Script, Visuals, Editing",
                            notes: "Let the opening breathe."
                        )
                    ]
                ),
                Scene(
                    id: problemID,
                    order: 1,
                    sectionType: .problem,
                    title: "Problem",
                    scriptText: "When those parts live in different apps, you lose rhythm. You write a line, then forget the visual. You plan a visual, then lose the reason it mattered.",
                    notes: "",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: problemSegmentID, sceneID: problemID, order: 0, sourceText: "When those parts live in different apps, you lose rhythm.", segmentType: .paragraph, timingEstimate: 5)
                    ],
                    aiComments: [],
                    bRollItems: [],
                    editingItems: []
                ),
                Scene(
                    id: explanationID,
                    order: 2,
                    sectionType: .explanation,
                    title: "Explanation",
                    scriptText: "FrameScript keeps every scene as one structured unit. You can write the voiceover, plan the supporting shots, and leave editor notes without breaking flow.",
                    notes: "",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: explanationSegmentID, sceneID: explanationID, order: 0, sourceText: "FrameScript keeps every scene as one structured unit.", segmentType: .paragraph, timingEstimate: 4)
                    ],
                    aiComments: [],
                    bRollItems: [],
                    editingItems: []
                )
            ],
            settingsOverride: nil,
            exportPresets: [
                ExportPreset(id: UUID(), name: "Editor handoff", format: .productionOutline)
            ]
        )
    }

    private static var russianDemoProject: FrameProject {
        let hookID = UUID()
        let problemID = UUID()
        let explanationID = UUID()
        let hookSegmentID = UUID()
        let problemSegmentID = UUID()
        let explanationSegmentID = UUID()

        return FrameProject(
            id: UUID(),
            title: "Новый сценарий YouTube",
            createdAt: Date(),
            updatedAt: Date(),
            templateID: templates.first?.id,
            scenes: [
                Scene(
                    id: hookID,
                    order: 0,
                    sectionType: .hook,
                    title: "Хук",
                    scriptText: "Большинство инструментов для авторов обращаются с видео как с пустой страницей. Но хорошее YouTube-видео - это не один документ. Это сценарий, визуальный план и ритм монтажа, которые движутся вместе.",
                    notes: "Начать с тезиса продукта, а не с перечисления функций.",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: hookSegmentID, sceneID: hookID, order: 0, sourceText: "Большинство инструментов для авторов обращаются с видео как с пустой страницей.", segmentType: .paragraph, timingEstimate: 4)
                    ],
                    aiComments: [
                        AIComment(
                            id: UUID(),
                            sceneID: hookID,
                            segmentID: hookSegmentID,
                            type: "Хук",
                            severity: .suggestion,
                            message: "Первая фраза понятная, но контраст можно сделать острее.",
                            suggestion: "Сначала назовите боль, а затем идею продукта.",
                            status: .new
                        )
                    ],
                    bRollItems: [
                        BRollItem(
                            id: UUID(),
                            linkedSegmentID: hookSegmentID,
                            templateType: "Запись экрана",
                            sourceType: .screenRecording,
                            descriptionText: "Быстрые переходы между пустым документом, таймлайном и разрозненными заметками.",
                            mood: "спокойное раздражение",
                            framing: "плотный фрагмент экрана",
                            motion: "медленный наезд",
                            duration: 6,
                            notes: "Сдержанно. Без кричащего монтажа.",
                            status: .planned
                        )
                    ],
                    editingItems: [
                        EditingItem(
                            id: UUID(),
                            linkedSegmentID: hookSegmentID,
                            templateType: "Образовательный YouTube",
                            cutStyle: "Чистые склейки",
                            transition: "Жесткая склейка",
                            subtitleStyle: "Только выделение ключевых слов",
                            emphasis: "Подсветить фразу 'не один документ'",
                            zoom: "Легкий наезд на тезис",
                            sfx: "",
                            musicCue: "Тихий фон после первой фразы",
                            graphics: "Три подписи: сценарий, видеоряд, монтаж",
                            notes: "Дайте вступлению дышать."
                        )
                    ]
                ),
                Scene(
                    id: problemID,
                    order: 1,
                    sectionType: .problem,
                    title: "Проблема",
                    scriptText: "Когда эти части живут в разных приложениях, теряется ритм. Вы пишете строку и забываете визуал. Планируете кадр и теряете причину, зачем он был нужен.",
                    notes: "",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: problemSegmentID, sceneID: problemID, order: 0, sourceText: "Когда эти части живут в разных приложениях, теряется ритм.", segmentType: .paragraph, timingEstimate: 5)
                    ],
                    aiComments: [],
                    bRollItems: [],
                    editingItems: []
                ),
                Scene(
                    id: explanationID,
                    order: 2,
                    sectionType: .explanation,
                    title: "Объяснение",
                    scriptText: "FrameScript держит каждую сцену как единую структурированную единицу. Вы пишете озвучку, планируете поддерживающие кадры и оставляете заметки редактору, не ломая поток.",
                    notes: "",
                    estimatedDuration: 0,
                    textSegments: [
                        TextSegment(id: explanationSegmentID, sceneID: explanationID, order: 0, sourceText: "FrameScript держит каждую сцену как единую структурированную единицу.", segmentType: .paragraph, timingEstimate: 4)
                    ],
                    aiComments: [],
                    bRollItems: [],
                    editingItems: []
                )
            ],
            settingsOverride: nil,
            exportPresets: [
                ExportPreset(id: UUID(), name: "Передача редактору", format: .productionOutline)
            ]
        )
    }
}
