import SwiftUI

struct ContentView: View {
    @StateObject private var arManager = ARSessionManager()

    var body: some View {
        ZStack {
            ARContainerView(arManager: arManager)
                .ignoresSafeArea()

            VStack {
                // Step-by-step guide card
                if arManager.state != .coaching {
                    guideCard
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }

                Spacer()

                // Bottom toolbar
                HStack(spacing: 12) {
                    if arManager.state == .calibrating {
                        Button(action: { arManager.confirmAlignment() }) {
                            Label("Confirm", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .loading {
                        ProgressView()
                            .tint(.white)
                    }

                    if arManager.state == .contentPlaced || arManager.state == .calibrating {
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

                // Debug log overlay
                if !arManager.debugLog.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(arManager.debugLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 60)
                }
            }
        }
    }

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Step indicator
            HStack(spacing: 0) {
                stepDot(step: 1, active: arManager.state == .aligning && arManager.alignmentPointCount == 0)
                stepLine(done: arManager.state != .aligning || arManager.alignmentPointCount > 0)
                stepDot(step: 2, active: arManager.state == .aligning && arManager.alignmentPointCount == 1)
                stepLine(done: arManager.state == .calibrating || arManager.state == .loading || arManager.state == .contentPlaced)
                stepDot(step: 3, active: arManager.state == .calibrating)
                stepLine(done: arManager.state == .loading || arManager.state == .contentPlaced)
                stepDot(step: 4, active: arManager.state == .loading || arManager.state == .contentPlaced)
            }

            // Current instruction
            Text(guideTitle)
                .font(.headline)
                .fontWeight(.semibold)

            Text(guideDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var guideTitle: String {
        switch arManager.state {
        case .coaching:
            return ""
        case .aligning where arManager.alignmentPointCount == 0:
            return "Step 1: Tap first point"
        case .aligning:
            return "Step 2: Tap second point"
        case .calibrating:
            return "Step 3: Fine-tune alignment"
        case .loading:
            return "Step 4: Loading model..."
        case .contentPlaced:
            return arManager.loadingError != nil ? "Error loading model" : "Step 4: Model loaded"
        }
    }

    private var guideDetail: String {
        switch arManager.state {
        case .coaching:
            return ""
        case .aligning where arManager.alignmentPointCount == 0:
            return "Tap on the floor at the base of a wall. This sets the first reference point."
        case .aligning:
            return "Tap a second point along the same wall edge on the floor. The line between the two points will align the grid."
        case .calibrating:
            return "The grid is aligned to your wall. Use two fingers to twist and fine-tune the angle, then tap Confirm."
        case .loading:
            return "Parsing IFC file and preparing 3D model..."
        case .contentPlaced:
            if let error = arManager.loadingError {
                return error
            }
            return "The IFC model is placed in your space. Tap Reset to start over."
        }
    }

    private func stepDot(step: Int, active: Bool) -> some View {
        let done = isStepDone(step)
        return ZStack {
            Circle()
                .fill(done ? .green : (active ? .cyan : .gray.opacity(0.3)))
                .frame(width: 24, height: 24)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(step)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? .white : .secondary)
            }
        }
    }

    private func stepLine(done: Bool) -> some View {
        Rectangle()
            .fill(done ? .green : .gray.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func isStepDone(_ step: Int) -> Bool {
        switch step {
        case 1:
            return arManager.alignmentPointCount >= 1 || arManager.state == .calibrating || arManager.state == .loading || arManager.state == .contentPlaced
        case 2:
            return arManager.state == .calibrating || arManager.state == .loading || arManager.state == .contentPlaced
        case 3:
            return arManager.state == .loading || arManager.state == .contentPlaced
        case 4:
            return arManager.state == .contentPlaced
        default:
            return false
        }
    }
}
