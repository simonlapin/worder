import SwiftUI
import UIKit

/// Design tokens: the brand comes from the app icon (blue→indigo gradient,
/// white flashcard). English headwords are set in a serif face like a
/// dictionary entry; Russian text stays in the system sans.
enum Theme {
    static let brandBlue = Color("BrandBlue")
    static let brandIndigo = Color("BrandIndigo")
    static let cardSurface = Color("CardSurface")

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandBlue, brandIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Dictionary-style face for English headwords.
    static func headword(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// Rounded numerals for counters and stats.
    static func counter(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// Brand-gradient capsule for the single main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.brandGradient, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Quiet tinted capsule for secondary actions and answer options.
struct AnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                Theme.brandBlue.opacity(configuration.isPressed ? 0.18 : 0.08),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.brandBlue.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The signature flashcard surface every exercise sits on.
struct WordCardModifier: ViewModifier {
    var tilt: Angle = .zero

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .padding(.horizontal, 24)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 28))
            .shadow(color: Theme.brandIndigo.opacity(0.10), radius: 24, y: 12)
            .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
            .rotationEffect(tilt)
    }
}

extension View {
    func wordCard(tilt: Angle = .zero) -> some View {
        modifier(WordCardModifier(tilt: tilt))
    }
}

/// Uppercase caption used as a small label above headwords and sections.
struct EyebrowText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundStyle(Theme.brandBlue)
    }
}

/// Brand-tinted rounded text field for answer input.
struct AnswerFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title3)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.brandBlue.opacity(0.35), lineWidth: 1)
            )
    }
}

extension View {
    func answerField() -> some View {
        modifier(AnswerFieldModifier())
    }
}

/// Slide-forward transition for exercise changes; plain fade when the user
/// prefers reduced motion.
enum ExerciseTransition {
    static var current: AnyTransition {
        if UIAccessibility.isReduceMotionEnabled {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}
