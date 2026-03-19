import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()

    var body: some View {
        Group {
            if viewModel.hasStarted {
                gameScreen
            } else {
                landingScreen
            }
        }
    }

    private var landingScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.16, green: 0.12, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Augmented Fantasy Chess")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("Deploy a dark-fantasy battlefield on your table, command House Stark, and fight an AI House Lannister army in AR.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))

                    Text("Choose Theme")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(BattleTheme.allCases) { theme in
                        Button {
                            viewModel.selectedTheme = theme
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(theme.title)
                                        .font(.headline)
                                    Text(theme.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer()
                                if viewModel.selectedTheme == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(viewModel.selectedTheme == theme ? Color.white.opacity(0.20) : Color.white.opacity(0.09))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Difficulty")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Picker("Difficulty", selection: $viewModel.difficulty) {
                        Text("Easy").tag(Difficulty.easy)
                        Text("Medium").tag(Difficulty.medium)
                        Text("Hard").tag(Difficulty.hard)
                    }
                    .pickerStyle(.segmented)

                    Button("Enter Battlefield") {
                        viewModel.startExperience()
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
    }

    private var gameScreen: some View {
        ZStack(alignment: .top) {
            ARChessView(viewModel: viewModel)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                topControls
                statusCard
                Spacer()
            }
            .padding(.top, 18)
            .padding(.horizontal, 14)
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button("Menu") {
                viewModel.returnToLanding()
            }
            .buttonStyle(BattleButtonStyle(color: Color(red: 0.22, green: 0.24, blue: 0.30)))

            Button("Reposition") {
                viewModel.startRepositionMode()
            }
            .buttonStyle(BattleButtonStyle(color: Color(red: 0.28, green: 0.30, blue: 0.36)))

            Button("Hint") {
                viewModel.requestHint()
            }
            .buttonStyle(BattleButtonStyle(color: Color(red: 0.26, green: 0.40, blue: 0.34)))
            .disabled(!viewModel.canInteract)

            Button("Reset") {
                viewModel.resetGame()
            }
            .buttonStyle(BattleButtonStyle(color: Color(red: 0.40, green: 0.26, blue: 0.24)))
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(viewModel.selectedTheme.title) Battlefield")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(2)

            Text(viewModel.sideInfoText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Text(viewModel.turnInfoText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct BattleButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.7 : 0.92))
            )
    }
}

#Preview {
    ContentView()
}
