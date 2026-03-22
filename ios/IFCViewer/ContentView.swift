import SwiftUI

struct ContentView: View {
    @StateObject private var arManager = ARSessionManager()

    var body: some View {
        ZStack {
            ARContainerView(arManager: arManager)
                .ignoresSafeArea()

            VStack {
                // Status bar at top (hidden during coaching — overlay handles it)
                if arManager.state != .coaching {
                    Text(arManager.statusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }

                Spacer()

                // Bottom toolbar
                HStack(spacing: 16) {
                    if arManager.state == .calibrating {
                        Button(action: { arManager.confirmAlignment() }) {
                            Label("Confirm Alignment", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.green.opacity(0.8), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .contentPlaced || arManager.state == .ready {
                        Button(action: { arManager.reset() }) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}
