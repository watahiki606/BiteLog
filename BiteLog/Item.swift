//
//  Item.swift
//  BiteLog
//
//  Created by 綿引慎也 on 2025/02/22.
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
