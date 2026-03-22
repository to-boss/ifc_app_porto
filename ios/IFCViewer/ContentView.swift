import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ContentView: View {
    @StateObject private var arManager = ARSessionManager()
    @State private var showDebugLog = false

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

                // Preview sliders (room or fixture)
                if arManager.state == .previewing || arManager.state == .fixturePreviewing {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Slider(value: $arManager.modelScale, in: 0.5...10.0)
                            Text(String(format: "%.1fx", arManager.modelScale))
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 40)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "rotate.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Slider(value: $arManager.modelRotation, in: 0...(2 * .pi))
                            Text(String(format: "%.0f", arManager.modelRotation * 180 / .pi) + "°")
                                .font(.system(size: 13, design: .monospaced))
                                .frame(width: 40)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                }

                // Fixture picker
                if arManager.state == .roomPlaced && arManager.selectedElement == nil {
                    fixturePicker
                        .padding(.horizontal, 20)
                }

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

                    if arManager.state == .previewing {
                        Button(action: { arManager.placeRoom() }) {
                            Label("Place Room", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .fixturePreviewing {
                        Button(action: { arManager.placeFixture() }) {
                            Label("Place Fixture", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .roomPlaced || arManager.state == .done {
                        Button(action: { arManager.exportMergedIFC() }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.orange.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .roomPlaced {
                        Button(action: { arManager.finishSession() }) {
                            Label("Done", systemImage: "checkmark.seal.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.blue.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    if arManager.state == .loading || arManager.state == .fixtureLoading {
                        ProgressView()
                            .tint(.white)
                    }

                    if [.calibrating, .previewing, .fixturePreviewing, .roomPlaced, .done].contains(arManager.state) {
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

                // Debug toggle + log overlay
                HStack {
                    Spacer()
                    Button(action: { showDebugLog.toggle() }) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 14))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(showDebugLog ? .green : .secondary)
                    }
                    .padding(.trailing, 12)
                }

                if showDebugLog && !arManager.debugLog.isEmpty {
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

            // Floating bubble action menu
            if let element = arManager.selectedElement, !arManager.showingDetails {
                elementBubble(element)
            }

            // Details sheet overlay
            if arManager.showingDetails, let element = arManager.selectedElement {

                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { arManager.dismissSelection() }

                elementDetailsView(element)
                    .padding(.horizontal, 20)
            }
        }
        .sheet(isPresented: Binding(
            get: { arManager.exportFileURL != nil },
            set: { if !$0 { arManager.exportFileURL = nil } }
        )) {
            if let url = arManager.exportFileURL {
                ShareSheet(items: [url])
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
                stepLine(done: isStepDone(2))
                stepDot(step: 3, active: arManager.state == .calibrating)
                stepLine(done: isStepDone(3))
                stepDot(step: 4, active: arManager.state == .loading || arManager.state == .previewing)
                stepLine(done: isStepDone(4))
                stepDot(step: 5, active: [.roomPlaced, .fixtureLoading, .fixturePreviewing, .done].contains(arManager.state))
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
            return "Step 4: Loading room..."
        case .previewing:
            return "Step 4: Position room"
        case .roomPlaced:
            return arManager.loadingError != nil ? "Error" : "Step 5: Add fixtures"
        case .fixtureLoading:
            return "Loading fixture..."
        case .fixturePreviewing:
            return "Position fixture"
        case .done:
            return "Complete"
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
            return "Parsing room IFC and preparing 3D model..."
        case .previewing:
            return "Move your device to position the room. Use the sliders to adjust scale and rotation, then tap Place Room."
        case .roomPlaced:
            if let error = arManager.loadingError {
                return error
            }
            return "Room is placed. Pick a fixture to add, or tap Done."
        case .fixtureLoading:
            return "Parsing fixture IFC..."
        case .fixturePreviewing:
            return "Move your device to position the fixture inside the room. Adjust with sliders, then tap Place Fixture."
        case .done:
            return "All models placed. Tap Reset to start over."
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
        let laterStates: Set<ARState> = [.roomPlaced, .fixtureLoading, .fixturePreviewing, .done]
        switch step {
        case 1:
            return arManager.alignmentPointCount >= 1 || arManager.state == .calibrating || arManager.state == .loading || arManager.state == .previewing || laterStates.contains(arManager.state)
        case 2:
            return arManager.state == .calibrating || arManager.state == .loading || arManager.state == .previewing || laterStates.contains(arManager.state)
        case 3:
            return arManager.state == .loading || arManager.state == .previewing || laterStates.contains(arManager.state)
        case 4:
            return laterStates.contains(arManager.state)
        case 5:
            return arManager.state == .done
        default:
            return false
        }
    }

    // MARK: - Fixture Picker

    private var fixturePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Fixture")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                fixtureButton(label: "Toilet", icon: "toilet", filename: "Objekt_WC")
                fixtureButton(label: "Sink", icon: "drop", filename: "Objekt_Waschbecken")
                fixtureButton(label: "Accessible WC", icon: "figure.roll", filename: "Objekt_WC_Beh_")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func fixtureButton(label: String, icon: String, filename: String) -> some View {
        Button(action: { arManager.loadFixture(named: filename) }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .frame(width: 80, height: 64)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Element Bubble

    private func elementBubble(_ element: ElementInfo) -> some View {
        GeometryReader { geo in
            let bubbleWidth: CGFloat = 220
            let bubbleHeight: CGFloat = 120
            let tapPt = arManager.selectedScreenPoint
            // Position bubble above the tap point, clamped to screen
            let x = min(max(tapPt.x - bubbleWidth / 2, 12), geo.size.width - bubbleWidth - 12)
            let y = min(max(tapPt.y - bubbleHeight - 20, 12), geo.size.height - bubbleHeight - 12)

            VStack(spacing: 8) {
                Text(element.name ?? element.ifcType)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Button(action: { arManager.moveSelectedElement() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.body)
                            Text("Move")
                                .font(.system(size: 9))
                        }
                        .frame(width: 56, height: 44)
                        .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: { arManager.showDetails() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "info.circle")
                                .font(.body)
                            Text("Details")
                                .font(.system(size: 9))
                        }
                        .frame(width: 56, height: 44)
                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: { arManager.deleteSelectedElement() }) {
                        VStack(spacing: 2) {
                            Image(systemName: "trash")
                                .font(.body)
                            Text("Delete")
                                .font(.system(size: 9))
                        }
                        .frame(width: 56, height: 44)
                        .background(.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .position(x: x + bubbleWidth / 2, y: y + bubbleHeight / 2)
        }
        .ignoresSafeArea()
    }

    // MARK: - Element Details

    private func elementDetailsView(_ element: ElementInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(element.name ?? "Unnamed")
                        .font(.headline)
                    Text(element.ifcType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { arManager.dismissSelection() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            if element.properties.isEmpty {
                Text("No properties")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        let grouped = Dictionary(grouping: element.properties, by: { $0.propertySet ?? "Other" })
                        ForEach(grouped.keys.sorted(), id: \.self) { pset in
                            Text(pset)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            ForEach(Array((grouped[pset] ?? []).enumerated()), id: \.offset) { _, prop in
                                HStack(alignment: .top) {
                                    Text(prop.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(prop.value)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
