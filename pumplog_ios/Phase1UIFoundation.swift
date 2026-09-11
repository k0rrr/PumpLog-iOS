import SwiftUI

struct Phase1PrimaryButton: View {
    let title: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(_ title: String, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(Phase1PrimaryButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier ?? "phase1PrimaryButton")
    }
}

struct Phase1SecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(Phase1SecondaryButtonStyle())
    }
}

/// 共通の44ptタップ領域を持つ、ナビゲーション用アイコンボタン。
/// 画面ごとにアイコンの当たり判定が変わらないようにする。
struct Phase1IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    init(_ systemName: String, label: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// 各タブの先頭タイトル。位置・サイズ・余白を共通化する。
struct Phase1TabHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

/// タブ内で使う検索欄。システム検索の配置に左右されず、ヘッダー直下に揃える。
struct Phase1SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Phase1DesignTokens.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Phase1DesignTokens.secondary)
                }
                .accessibilityLabel("検索をクリア")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Phase1DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("履歴を検索")
    }
}

private struct Phase1PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Phase1DesignTokens.orangeGradient)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct Phase1SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Phase1DesignTokens.orange)
            .background(Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Phase1DesignTokens.orange))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum Phase1DesignTokens {
    static let background = Color(red: 0.071, green: 0.071, blue: 0.071) // #121212
    static let card = Color(red: 0.105, green: 0.105, blue: 0.11) // #1B1B1C
    static let divider = Color.white.opacity(0.10)
    static let secondary = Color(red: 0.56, green: 0.56, blue: 0.58)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.05) // Figma accent
    /// App iconと同じ、上部の明るいオレンジから下部の赤みオレンジへ変化するCTA用グラデーション。
    static let orangeGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.68, blue: 0.08),
            Color(red: 1.0, green: 0.32, blue: 0.02)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// UI-facing names used by the Figma screens. Stored names remain unchanged
/// so existing SwiftData records and lookups continue to work.
func phase1DisplayExerciseName(_ exercise: Phase1Exercise?) -> String {
    guard let exercise else { return "種目" }
    switch exercise.seedKey {
    case "bench_press": return "Bench Press"
    case "incline_dumbbell_press": return "Incline DB Press"
    case "cable_fly": return "Cable Fly"
    case "push_down": return "Triceps Pushdown"
    default: return exercise.name
    }
}

func phase1JapaneseDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy年M月d日"
    return formatter.string(from: date)
}

func phase1ShortJapaneseDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "M/d (E)"
    return formatter.string(from: date)
}

func phase1MonthTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy年M月"
    return formatter.string(from: date)
}

func phase1SlashDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy/M/d"
    return formatter.string(from: date)
}

func shortDateWithWeekday(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "M/d (E)"
    return formatter.string(from: date)
}
