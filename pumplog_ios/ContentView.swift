//
//  ContentView.swift
//  pumplog_ios
//
//  Created by Kairi Tayama on 2026/08/07.
//

import SwiftUI

struct WorkoutRecord : Identifiable {
    let id = UUID()
    let name : String
    let weight : String
    let reps : String
}
struct ContentView: View {
    @State private var exerciseName = ""
    @State private var exerciseWeight = ""
    @State private var exerciseReps = ""
    @State private var records : [WorkoutRecord] = []
    var body: some View{
        VStack{
            Text("PumpLog")
            TextField("種目名", text: $exerciseName)
            TextField("重量", text: $exerciseWeight)
            TextField("回数", text: $exerciseReps)
            Button("記録する"){
                let newRecord = WorkoutRecord(
                    name: exerciseName,
                    weight:exerciseWeight,
                    reps: exerciseReps
                )
                
                records.append(newRecord)
                
                exerciseName = ""
                exerciseWeight = ""
                exerciseReps = ""
            }
            ForEach(records) { record in
                Text("\(record.name)\(record.weight)kg×\(record.reps)回")
        
            }
            
        }
    }
}

        

#Preview {
    ContentView()
}
