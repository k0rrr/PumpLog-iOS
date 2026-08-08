//
//  ContentView.swift
//  pumplog_ios
//
//  Created by Kairi Tayama on 2026/08/07.
//

import SwiftUI
struct WorkoutSet : Identifiable {
    let id = UUID()
    let weight: String
    let reps: String
}
struct WorkoutRecord : Identifiable {
    let id = UUID()
    let name : String
    var sets: [WorkoutSet]
}
struct ContentView: View {
    @State private var exerciseName = "ベンチプレス"
    @State private var exerciseWeight = ""
    @State private var exerciseReps = ""
    @State private var records : [WorkoutRecord] = []
    @State private var showError = false
    let exercises = [
        "ベンチプレス",
        "スクワット",
        "デッドリフト"
    ]
    var body: some View{
        VStack{
            Text("PumpLog")
            //TextField("種目名", text: $exerciseName)
            Picker("種目",selection: $exerciseName) {
                ForEach(exercises, id:\.self){exercise in
                    Text(exercise)
                        .tag(exercise)
                }
            }
            TextField("重量", text: $exerciseWeight)
            TextField("回数", text: $exerciseReps)
            Button("記録する"){
                if exerciseName != "" && exerciseWeight != "" && exerciseReps != ""{
                    let newSet = WorkoutSet(
                        weight:exerciseWeight,
                        reps: exerciseReps
                    )
                    if let index = records.firstIndex(where: {record in
                        record.name == exerciseName
                    }) {
                        records[index].sets.append(newSet)
                    }else {
                        let newRecord = WorkoutRecord(
                            name: exerciseName,
                            sets: [newSet]
                        )
                        records.append(newRecord)
                    }
                    exerciseWeight = ""
                    exerciseReps = ""
                    showError = false
                }else{
                    showError = true
                    
                }
            }
            Button("前回の記録を使う"){
                let sameExerciseRecords = records.filter { record in
                    record.name == exerciseName
                }
                if let lastRecord = sameExerciseRecords.last {
                    if let lastSet = lastRecord.sets.last {
                        exerciseWeight = lastSet.weight
                        exerciseReps = lastSet.reps
                    }
                }
            }
        }
        
        if showError {
            Text("全て入力してください")
        }
        ForEach(records) { record in
            Text(record.name)
            ForEach(record.sets) { set in
                Text("\(set.weight)kg×\(set.reps)回")
                
            }
            
        }
    }
}

        

#Preview {
    ContentView()
}
