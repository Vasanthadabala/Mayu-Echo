//
//  Mayu_EchoApp.swift
//  Mayu Echo
//
//  Created by Vasanth on 06/05/26.
//

import SwiftUI
import SwiftData

@main
struct Mayu_EchoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
        .modelContainer(sharedModelContainer)
    }
}
