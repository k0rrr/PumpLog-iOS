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
                    let newRecord = WorkoutRecord(
                        name: exerciseName,
                        weight:exerciseWeight,
                        reps: exerciseReps
                    )
                    records.append(newRecord)
                    exerciseWeight = ""
                    exerciseReps = ""
                    showError = false
                }else{
                    showError = true
                    
                }
            }
            Button("前回の記録を使う"){
                let semeExerciseRecords = records.filter { record in
                    record.name == exerciseName
                }
                if let lastRecord = semeExerciseRecords.last {
                    exerciseWeight = lastRecord.weight
                    exerciseReps = lastRecord.reps
                    }
            }
        }
            
            if showError {
                Text("全て入力してください")
            }
            ForEach(records) { record in
                Text("\(record.name)\(record.weight)kg×\(record.reps)回")
        
            }
            
        }
    }


        

#Preview {
    ContentView()
}
