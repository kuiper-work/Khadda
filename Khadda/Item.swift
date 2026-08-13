//
//  Item.swift
//  Khadda
//
//  Created by Jay Desai on 10/01/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
