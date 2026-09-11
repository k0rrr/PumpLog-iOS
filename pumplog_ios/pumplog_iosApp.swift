//
//  pumplog_iosApp.swift
//  pumplog_ios
//
//  Created by Kairi Tayama on 2026/08/07.
//

import SwiftUI
import SwiftData

@main
struct pumplog_iosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Phase1Exercise.self,
            Phase1Workout.self,
            Phase1WorkoutExercise.self,
            Phase1WorkoutSet.self
        ])
    }
}
