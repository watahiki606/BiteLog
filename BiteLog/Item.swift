//
//  Item.swift
//  BiteLog
//
//  Created by 綿引慎也 on 2025/02/22.
//

import Foundation
import SwiftData

enum MealType: String, CaseIterable, Codable {
    case breakfast = "朝食"
    case lunch = "昼食"
    case dinner = "夕食"
    case snack = "間食"
}

@Model
final class Item {
    var name: String
    var calories: Double
    var protein: Double
    var fat: Double
    var carbohydrates: Double
    var mealType: MealType
    var timestamp: Date
    
    init(name: String, calories: Double, protein: Double, fat: Double, carbohydrates: Double, mealType: MealType, timestamp: Date) {
        self.name = name
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbohydrates = carbohydrates
        self.mealType = mealType
        self.timestamp = timestamp
    }
}
