import SwiftData
import XCTest
@testable import pumplog_ios

@MainActor
final class Phase1WorkoutViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Phase1Exercise.self, Phase1Workout.self,
            Phase1WorkoutExercise.self, Phase1WorkoutSet.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeActiveWorkout(in context: ModelContext, exercise: Phase1Exercise) -> (Phase1Workout, Phase1WorkoutExercise) {
        let workout = Phase1Workout(startedAt: Date(timeIntervalSince1970: 2_000), status: .active)
        let entry = Phase1WorkoutExercise(orderIndex: 0, workout: workout, exercise: exercise)
        context.insert(workout)
        context.insert(entry)
        return (workout, entry)
    }

    func testCompleteSetKeepsEnteredWeightAndIgnoresSecondTapDuringRest() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Incline DB Press", muscleGroup: .chest, weightStep: 1)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.selectedEntryID = entry.id
        viewModel.selectedWeight = 21
        viewModel.selectedReps = 8

        viewModel.completeSet()
        viewModel.completeSet()

        XCTAssertEqual(entry.sets.filter { $0.completedAt != nil }.count, 1)
        XCTAssertEqual(entry.sets.first?.weight, 21)
        XCTAssertEqual(entry.sets.first?.reps, 8)
        XCTAssertEqual(viewModel.selectedWeight, 21)
        XCTAssertEqual(viewModel.selectedReps, 8)
        XCTAssertNotNil(workout.restEndAt)

        // After the rest period, the next set should inherit today's last
        // value rather than falling back to the previous workout.
        workout.restEndAt = nil
        viewModel.selectedWeight = 20
        viewModel.selectedReps = 1
        viewModel.loadDefaults()
        XCTAssertEqual(viewModel.selectedWeight, 21)
        XCTAssertEqual(viewModel.selectedReps, 8)
    }

    func testCompleteSetPersistsWeightAndRepsToSwiftData() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, weightStep: 2.5)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.selectedEntryID = entry.id
        viewModel.selectedWeight = 21
        viewModel.selectedReps = 7
        viewModel.completeSet()

        let saved = try XCTUnwrap(entry.sets.first)
        XCTAssertEqual(saved.weight, 20, "weightStep 2.5 should normalize 21kg to 20kg")
        XCTAssertEqual(saved.reps, 7)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Phase1WorkoutSet>()).count, 1)
    }

    func testPreviousRecordReturnsMatchingSetNumber() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, weightStep: 2.5)
        context.insert(exercise)

        let previous = Phase1Workout(startedAt: Date(timeIntervalSince1970: 1_000), status: .completed)
        let previousEntry = Phase1WorkoutExercise(orderIndex: 0, workout: previous, exercise: exercise)
        let previousSet = Phase1WorkoutSet(setNumber: 2, weight: 22.5, reps: 6, completedAt: previous.startedAt, workoutExercise: previousEntry)
        previousEntry.sets.append(previousSet)
        previous.workoutExercises.append(previousEntry)
        context.insert(previous)
        context.insert(previousEntry)
        context.insert(previousSet)
        try context.save()

        let value = Phase1PreviousRecordService.value(for: exercise, setNumber: 2, before: Date(timeIntervalSince1970: 2_000), in: context)
        XCTAssertTrue(value.isAvailable)
        XCTAssertEqual(value.weight, 22.5)
        XCTAssertEqual(value.reps, 6)
    }

    func testStartingWorkoutDoesNotCreateDuplicateActiveSessions() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(exercise)
        try context.save()

        let viewModel = Phase1WorkoutSetupViewModel(groups: [.chest])
        viewModel.load(context: context)
        let first = try XCTUnwrap(viewModel.start())
        let second = try XCTUnwrap(viewModel.start())

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Phase1Workout>()).filter { $0.status == .active }.count, 1)
        XCTAssertEqual(first.workoutExercises.count, 1)
    }

    func testFinishingWorkoutPersistsCompletedStatusAfterRecordedSet() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, weightStep: 1)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.selectedEntryID = entry.id
        viewModel.selectedWeight = 21
        viewModel.selectedReps = 8
        viewModel.completeSet()

        guard case .completed(let id) = viewModel.finish() else {
            return XCTFail("A workout with a completed set should finish successfully")
        }
        XCTAssertEqual(id, workout.id)
        XCTAssertEqual(workout.status, .completed)
        XCTAssertNotNil(workout.endedAt)
        XCTAssertNil(workout.restEndAt)
    }

    func testEditingSetUpdatesValueAndPersistsAfterReload() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, weightStep: 1)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        let set = Phase1WorkoutSet(setNumber: 1, weight: 20, reps: 8, completedAt: workout.startedAt, workoutExercise: entry)
        entry.sets.append(set)
        context.insert(set)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.editSet(id: set.id, weight: 21, reps: 10)

        XCTAssertEqual(set.weight, 21)
        XCTAssertEqual(set.reps, 10)
        // A fresh ModelContext mirrors the app being terminated and launched
        // again while using the same persistent container.
        let reloadedContext = ModelContext(context.container)
        let reloaded = try XCTUnwrap(try reloadedContext.fetch(FetchDescriptor<Phase1WorkoutSet>()).first { $0.id == set.id })
        XCTAssertEqual(reloaded.weight, 21)
        XCTAssertEqual(reloaded.reps, 10)
    }

    func testDeletingSetRemovesItAndRenumbersRemainingSets() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, weightStep: 1)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        let first = Phase1WorkoutSet(setNumber: 1, weight: 20, reps: 8, completedAt: workout.startedAt, workoutExercise: entry)
        let second = Phase1WorkoutSet(setNumber: 2, weight: 21, reps: 8, completedAt: workout.startedAt.addingTimeInterval(1), workoutExercise: entry)
        entry.sets = [first, second]
        context.insert(first); context.insert(second)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.deleteSet(first)

        XCTAssertEqual(entry.sets.count, 1)
        XCTAssertEqual(entry.sets.first?.id, second.id)
        XCTAssertEqual(entry.sets.first?.setNumber, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Phase1WorkoutSet>()).count, 1)
    }

    func testExerciseSelectionIsPersistedAndRestoredForNextSession() throws {
        let context = try makeContext()
        let firstExercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest)
        let secondExercise = Phase1Exercise(name: "Incline DB Press", muscleGroup: .chest)
        context.insert(firstExercise); context.insert(secondExercise)
        let workout = Phase1Workout(startedAt: Date(timeIntervalSince1970: 2_000), status: .active)
        let firstEntry = Phase1WorkoutExercise(orderIndex: 0, workout: workout, exercise: firstExercise)
        let secondEntry = Phase1WorkoutExercise(orderIndex: 1, workout: workout, exercise: secondExercise)
        workout.workoutExercises = [firstEntry, secondEntry]
        context.insert(workout); context.insert(firstEntry); context.insert(secondEntry)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id)
        viewModel.configure(context: context)
        viewModel.selectedWeight = 37
        viewModel.selectedReps = 15
        viewModel.select(secondEntry.id)
        XCTAssertEqual(workout.selectedWorkoutExerciseID, secondEntry.id)
        XCTAssertEqual(viewModel.selectedWeight, Phase1Defaults.defaultWeight)
        XCTAssertEqual(viewModel.selectedReps, Phase1Defaults.defaultReps)

        let nextViewModel = Phase1WorkoutViewModel(workoutID: workout.id)
        nextViewModel.configure(context: context)
        XCTAssertEqual(nextViewModel.selectedEntryID, secondEntry.id)
        XCTAssertEqual(nextViewModel.selectedExercise?.id, secondExercise.id)
    }

    func testMuscleSelectionSupportsMultipleIndependentGroups() {
        let viewModel = Phase1MuscleSelectionViewModel()
        viewModel.toggle(.chest)
        viewModel.toggle(.back)
        XCTAssertEqual(viewModel.selected, [.chest, .back])

        viewModel.toggle([.biceps, .triceps])
        XCTAssertEqual(viewModel.selected, [.chest, .back, .biceps, .triceps])
        viewModel.toggle(.back)
        XCTAssertFalse(viewModel.selected.contains(.back))
    }

    func testExpiredRestCanBeRestartedAndExtended() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest, restDuration: 90)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        context.insert(entry)
        workout.restEndAt = Date(timeIntervalSince1970: 2_090)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 2_100) })
        viewModel.configure(context: context)
        viewModel.setRestDuration(minutes: 1)
        XCTAssertEqual(workout.restEndAt, Date(timeIntervalSince1970: 2_160))

        viewModel.addRestTime(30)
        XCTAssertEqual(workout.restEndAt, Date(timeIntervalSince1970: 2_190))
    }

    func testRestDurationSupportsMinuteAndSecondPrecision() throws {
        let context = try makeContext()
        let exercise = Phase1Exercise(name: "Bench Press", muscleGroup: .chest)
        context.insert(exercise)
        let (workout, entry) = makeActiveWorkout(in: context, exercise: exercise)
        context.insert(entry)
        try context.save()

        let viewModel = Phase1WorkoutViewModel(workoutID: workout.id, now: { Date(timeIntervalSince1970: 3_000) })
        viewModel.configure(context: context)
        viewModel.setRestDuration(seconds: 75)
        XCTAssertEqual(workout.restEndAt, Date(timeIntervalSince1970: 3_075))

        viewModel.setRestDuration(seconds: 999)
        XCTAssertEqual(workout.restEndAt, Date(timeIntervalSince1970: 3_600), "休憩時間は最大10分に制限する")

        viewModel.setRestDuration(seconds: 0)
        XCTAssertNil(workout.restEndAt)
    }
}
