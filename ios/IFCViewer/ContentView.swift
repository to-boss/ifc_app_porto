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
    @State private var showFixturePicker = false
    @State private var showBCFSheet = false
    @State private var showBCFList = false
    @State private var bcfTitle = ""
    @State private var bcfDescription = ""
    @State private var bcfPriority = "Normal"
    @State private var bcfStatus = "Open"
    @State private var bcfAssignee = ""
    @State private var exportURLs: [URL] = []
    @State private var capturedSnapshot: UIImage?
    @State private var capturedViewpoint: ARSessionManager.CameraViewpoint?
    @State private var bcfElementGlobalId: String?
    @State private var bcfElementIfcType: String?

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

                // (fixture picker moved to sidebar overlay)

                // Debug log (above toolbar)
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
                }

                // Bottom toolbar
                HStack {
                    // Primary action (left)
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
                    } else if arManager.state == .previewing {
                        Button(action: { arManager.placeRoom() }) {
                            Label("Place Room", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    } else if arManager.state == .fixturePreviewing {
                        Button(action: { arManager.placeFixture() }) {
                            Label("Place Fixture", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.green.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    } else if arManager.state == .wallStart || arManager.state == .wallEnd {
                        HStack(spacing: 12) {
                            Button(action: {
                                if arManager.state == .wallStart {
                                    arManager.placeWallStart()
                                } else {
                                    arManager.placeWallEnd()
                                }
                            }) {
                                Label("Place", systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(.green.opacity(0.85), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Button(action: { arManager.cancelWallBuilding() }) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    } else if arManager.state == .wallAdjust {
                        HStack(spacing: 12) {
                            Button(action: { arManager.confirmWall() }) {
                                Label("Confirm", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(.green.opacity(0.85), in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Button(action: { arManager.cancelWallBuilding() }) {
                                Label("Cancel", systemImage: "xmark")
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                    } else if arManager.state == .roomPlaced {
                        Button(action: { arManager.finishSession() }) {
                            Label("Done", systemImage: "checkmark.seal.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.blue.opacity(0.85), in: Capsule())
                                .foregroundStyle(.white)
                        }
                    } else if arManager.state == .loading || arManager.state == .fixtureLoading {
                        ProgressView()
                            .tint(.white)
                    }

                    Spacer()

                    // Secondary actions (right)
                    HStack(spacing: 10) {
                        if [.calibrating, .previewing, .fixturePreviewing, .roomPlaced, .wallStart, .wallEnd, .wallAdjust, .done].contains(arManager.state) {
                            Button(action: { arManager.reset() }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title3)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }

                        Button(action: { showDebugLog.toggle() }) {
                            Image(systemName: "ladybug")
                                .font(.title3)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .foregroundStyle(showDebugLog ? .green : .secondary)
                        }

                        if arManager.state == .roomPlaced || arManager.state == .done {
                            Menu {
                                Button(action: { exportAll() }) {
                                    Label("Export All", systemImage: "arrow.down.doc")
                                }
                                Button(action: { arManager.exportMergedIFC() }) {
                                    Label("Export IFC", systemImage: "square.and.arrow.up")
                                }
                                if !arManager.bcfIssues.isEmpty {
                                    Button(action: { exportBCFOnly() }) {
                                        Label("Export BCF", systemImage: "doc.zipper")
                                    }
                                }
                                Button(action: { startBCFReport(element: nil) }) {
                                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                                }
                                if !arManager.bcfIssues.isEmpty {
                                    Button(action: { showBCFList = true }) {
                                        Label("BCF Issues (\(arManager.bcfIssues.count))", systemImage: "doc.text")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title2)
                                    .padding(10)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }

            // Wall dimension sliders
            if arManager.state == .wallAdjust {
                // Horizontal width slider at bottom
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.and.right")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Slider(value: $arManager.wallThickness, in: 0.05...1.0)
                        Text(String(format: "%.0f cm", arManager.wallThickness * 100))
                            .font(.system(size: 13, design: .monospaced))
                            .frame(width: 55)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 80)
                }

                // Vertical height slider on right edge
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text(String(format: "%.1fm", arManager.wallHeight))
                            .font(.system(size: 11, design: .monospaced))
                        Slider(value: $arManager.wallHeight, in: 0.5...5.0)
                            .frame(width: 150)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 30, height: 150)
                        Image(systemName: "arrow.up.and.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.trailing, 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }

            // Fixture sidebar
            if arManager.state == .roomPlaced && arManager.selectedElement == nil {
                fixtureSidebar
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
        .sheet(isPresented: Binding(
            get: { !exportURLs.isEmpty },
            set: { if !$0 { exportURLs = [] } }
        )) {
            ShareSheet(items: exportURLs)
        }
        .sheet(isPresented: $showBCFSheet) {
            bcfFormSheet
        }
        .sheet(isPresented: $showBCFList) {
            bcfListSheet
        }
    }

    // MARK: - BCF

    private func startBCFReport(element: ElementInfo?) {
        bcfElementGlobalId = element?.globalId
        bcfElementIfcType = element?.ifcType
        bcfTitle = ""
        bcfDescription = ""
        bcfPriority = "Normal"
        bcfStatus = "Open"
        bcfAssignee = ""

        // Capture snapshot + viewpoint before showing the sheet
        capturedViewpoint = arManager.currentViewpoint()
        Task {
            capturedSnapshot = await arManager.captureSnapshot()
            showBCFSheet = true
        }
    }

    private var bcfFormSheet: some View {
        NavigationView {
            Form {
                Section("Issue Details") {
                    TextField("Title", text: $bcfTitle)
                    TextField("Description", text: $bcfDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Classification") {
                    Picker("Priority", selection: $bcfPriority) {
                        ForEach(["Low", "Normal", "High", "Critical"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Status", selection: $bcfStatus) {
                        ForEach(["Open", "In Progress", "Closed"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    TextField("Assignee", text: $bcfAssignee)
                }
                if bcfElementGlobalId != nil {
                    Section("Linked Element") {
                        Label(bcfElementIfcType ?? "Element", systemImage: "cube")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Create BCF Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBCFSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Issue") { addBCFIssue() }
                        .disabled(bcfTitle.isEmpty)
                }
            }
        }
    }

    private func addBCFIssue() {
        guard let snapshot = capturedSnapshot,
              let viewpoint = capturedViewpoint else {
            arManager.log("BCF: missing snapshot or viewpoint")
            return
        }

        let issue = BCFIssue(
            title: bcfTitle,
            description: bcfDescription,
            priority: bcfPriority,
            status: bcfStatus,
            assignee: bcfAssignee,
            author: UIDevice.current.name,
            cameraPosition: viewpoint.position,
            cameraDirection: viewpoint.direction,
            cameraUp: viewpoint.up,
            fieldOfView: viewpoint.fieldOfView,
            selectedGlobalId: bcfElementGlobalId,
            selectedIfcType: bcfElementIfcType,
            snapshot: snapshot
        )

        arManager.bcfIssues.append(issue)
        arManager.log("BCF issue added: \(issue.title) (\(arManager.bcfIssues.count) total)")
        showBCFSheet = false
    }

    private func exportAll() {
        var urls: [URL] = []

        // Export IFC
        arManager.exportMergedIFC()
        if let ifcURL = arManager.exportFileURL {
            urls.append(ifcURL)
            arManager.exportFileURL = nil
        }

        // Export BCF if there are issues
        if !arManager.bcfIssues.isEmpty {
            do {
                let bcfURL = try BCFExporter.export(issues: arManager.bcfIssues)
                urls.append(bcfURL)
                arManager.log("BCF exported \(arManager.bcfIssues.count) issues")
            } catch {
                arManager.log("BCF export failed: \(error)")
            }
        }

        if !urls.isEmpty {
            exportURLs = urls
        }
    }

    private func exportBCFOnly() {
        do {
            let url = try BCFExporter.export(issues: arManager.bcfIssues)
            arManager.log("BCF exported \(arManager.bcfIssues.count) issues: \(url.lastPathComponent)")
            showBCFList = false
            arManager.exportFileURL = url
        } catch {
            arManager.log("BCF export failed: \(error)")
        }
    }

    private var bcfListSheet: some View {
        NavigationView {
            List {
                ForEach(Array(arManager.bcfIssues.enumerated()), id: \.offset) { index, issue in
                    HStack(spacing: 12) {
                        Image(uiImage: issue.snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(issue.priority)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.2), in: Capsule())
                                Text(issue.status)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if issue.selectedGlobalId != nil {
                                    Image(systemName: "cube")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    arManager.bcfIssues.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("BCF Issues (\(arManager.bcfIssues.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showBCFList = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export BCF") { exportBCFOnly() }
                        .disabled(arManager.bcfIssues.isEmpty)
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
                stepLine(done: isStepDone(2))
                stepDot(step: 3, active: arManager.state == .calibrating)
                stepLine(done: isStepDone(3))
                stepDot(step: 4, active: arManager.state == .loading || arManager.state == .previewing)
                stepLine(done: isStepDone(4))
                stepDot(step: 5, active: [.roomPlaced, .fixtureLoading, .fixturePreviewing, .wallStart, .wallEnd, .wallAdjust, .done].contains(arManager.state))
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
        case .wallStart:
            return "Place wall start"
        case .wallEnd:
            return "Place wall end"
        case .wallAdjust:
            return "Adjust wall"
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
        case .wallStart:
            return "Move your device to position the start point, then tap Place."
        case .wallEnd:
            return "Move to extend the wall. Tap Place to set the endpoint."
        case .wallAdjust:
            return "Use sliders to set height and width, then Confirm."
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
        let laterStates: Set<ARState> = [.roomPlaced, .fixtureLoading, .fixturePreviewing, .wallStart, .wallEnd, .wallAdjust, .done]
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

    private var fixtureSidebar: some View {
        HStack(spacing: 0) {
            if showFixturePicker {
                ScrollView {
                    VStack(spacing: 8) {
                        fixtureButton(label: "Toilet", icon: "toilet", filename: "Objekt_WC")
                        fixtureButton(label: "Sink", icon: "drop", filename: "Objekt_Waschbecken")
                        fixtureButton(label: "Access. WC", icon: "figure.roll", filename: "Objekt_WC_Beh_")

                        Button(action: {
                            arManager.startWallBuilding()
                            withAnimation(.spring(duration: 0.3)) { showFixturePicker = false }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.split.bottomrightquarter")
                                    .font(.title3)
                                Text("Wall")
                                    .font(.system(size: 9))
                                    .fontWeight(.medium)
                            }
                            .frame(width: 64, height: 56)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                }
                .frame(width: 80)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Button(action: { withAnimation(.spring(duration: 0.3)) { showFixturePicker.toggle() } }) {
                Image(systemName: showFixturePicker ? "xmark" : "plus.square.on.square")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.leading, showFixturePicker ? 4 : 0)

            Spacer()
        }
        .padding(.leading, 12)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func fixtureButton(label: String, icon: String, filename: String) -> some View {
        Button(action: {
            arManager.loadFixture(named: filename)
            withAnimation(.spring(duration: 0.3)) { showFixturePicker = false }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.system(size: 9))
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 64, height: 56)
            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Element Bubble

    private func elementBubble(_ element: ElementInfo) -> some View {
        GeometryReader { geo in
            let bubbleWidth: CGFloat = 280
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

                    Button(action: { startBCFReport(element: element) }) {
                        VStack(spacing: 2) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.body)
                            Text("Report")
                                .font(.system(size: 9))
                        }
                        .frame(width: 56, height: 44)
                        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
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
