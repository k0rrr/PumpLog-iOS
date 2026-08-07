//
//  ContentView.swift
//  pumplog_ios
//
//  Created by Kairi Tayama on 2026/08/07.
//

import SwiftUI


struct ContentView: View {
    @State private var exerciseName = ""
    @State private var exerciseWeight = ""
    @State private var exerciseReps = ""
    
    var body: some View{
        VStack{
            Text("PumpLog")
            TextField("種目名", text: $exerciseName)
            TextField("重量", text: $exerciseWeight)
            TextField("回数", text: $exerciseReps)
            Button("記録する"){
                print(exerciseName,exerciseWeight,exerciseReps)
            }
        }
    }
}

        

#Preview {
    ContentView()
}
