//
//  Item.swift
//  Mayu Echo
//
//  Created by Vasanth on 06/05/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var title: String = "Untitled"
    var isProject: Bool = false
    var projectPath: String?
    var parentProjectPath: String?
    var projectBookmarkData: Data?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.chat)
    var messages: [ChatMessageRecord] = []
    
    init(
        timestamp: Date,
        title: String,
        isProject: Bool = false,
        projectPath: String? = nil,
        parentProjectPath: String? = nil,
        projectBookmarkData: Data? = nil
    ) {
        self.timestamp = timestamp
        self.title = title
        self.isProject = isProject
        self.projectPath = projectPath
        self.parentProjectPath = parentProjectPath
        self.projectBookmarkData = projectBookmarkData
    }
}
