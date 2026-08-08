//
//  ContentView.swift
//  pumplog_ios
//
//  Created by Kairi Tayama on 2026/08/07.
//

import SwiftUI
struct WorkoutSet : Identifiable {
    let id = UUID()
    var weight: String
    var reps: String
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
    @State private var currentSets: [WorkoutSet] = []
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
            Button("前回の記録を使う"){
                let sameExerciseRecords = records.filter { record in
                    record.name == exerciseName
                }
                if let lastRecord = sameExerciseRecords.last {
                    currentSets = lastRecord.sets
                }
            }
            Button("セット追加"){
                if exerciseWeight != "" && exerciseReps != ""{
                    let newSet = WorkoutSet(
                        weight: exerciseWeight,
                        reps: exerciseReps
                    )
                    currentSets.append(newSet)
                    exerciseWeight = ""
                    exerciseReps = ""
                    showError = false
                }
            }
            ForEach(Array(currentSets.enumerated()),id: \.element.id) { index,set in
                HStack{
                    Text("Set\(index+1)")
                    TextField("重量",text: $currentSets[index].weight)
                    TextField("回数", text: $currentSets[index].reps)
                    Button("削除"){
                        currentSets.remove(at: index)
                    }
                }
            }
            Button("記録する"){
                if exerciseName != "" && !currentSets.isEmpty{
                    let newRecord = WorkoutRecord(
                        name: exerciseName,
                        sets: currentSets
                    )
                    records.append(newRecord)
                    currentSets = []
                    showError = false
                }else{
                    showError = true
                    
                }
            }
            
            
            
            if showError {
                Text("全て入力してください")
            }
            ForEach(records) { record in
                Text(record.name)
                ForEach(Array(record.sets.enumerated()),id:\.element.id) { index,set in
                    Text("Set\(index + 1) \(set.weight)kg×\(set.reps)回")
                    
                }
                
            }
            
            
            
        }
    }
}

#Preview {
    ContentView()
}
