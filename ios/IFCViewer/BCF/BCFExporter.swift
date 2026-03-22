import Foundation
import UIKit

struct BCFIssue {
    let title: String
    let description: String
    let priority: String
    let status: String
    let assignee: String
    let author: String

    let cameraPosition: SIMD3<Float>
    let cameraDirection: SIMD3<Float>
    let cameraUp: SIMD3<Float>
    let fieldOfView: Float // degrees

    let selectedGlobalId: String?
    let selectedIfcType: String?

    let snapshot: UIImage
}

enum BCFExporter {

    static func export(issues: [BCFIssue]) throws -> URL {
        let batchId = UUID().uuidString.lowercased().prefix(8)
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcf_\(batchId)")
        try? FileManager.default.removeItem(at: baseDir)
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        // Root-level files
        try versionXML().data(using: .utf8)!.write(to: baseDir.appendingPathComponent("bcf.version"))
        try extensionsXML().data(using: .utf8)!.write(to: baseDir.appendingPathComponent("extensions.xml"))

        // One topic folder per issue
        for issue in issues {
            let topicGuid = UUID().uuidString.lowercased()
            let viewpointGuid = UUID().uuidString.lowercased()
            let commentGuid = UUID().uuidString.lowercased()

            let topicDir = baseDir.appendingPathComponent(topicGuid)
            try FileManager.default.createDirectory(at: topicDir, withIntermediateDirectories: true)

            try markupXML(issue: issue, topicGuid: topicGuid, viewpointGuid: viewpointGuid, commentGuid: commentGuid)
                .data(using: .utf8)!.write(to: topicDir.appendingPathComponent("markup.bcf"))
            try viewpointXML(issue: issue, viewpointGuid: viewpointGuid)
                .data(using: .utf8)!.write(to: topicDir.appendingPathComponent("viewpoint.bcfv"))
            let snapshotData = issue.snapshot.jpegData(compressionQuality: 0.7) ?? Data()
            try snapshotData.write(to: topicDir.appendingPathComponent("snapshot.jpg"))
        }

        // Zip
        let bcfzipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IFC-AR-Issues-\(batchId).bcfzip")
        try createZip(from: baseDir, to: bcfzipURL)

        // Cleanup temp dir
        try? FileManager.default.removeItem(at: baseDir)

        return bcfzipURL
    }

    // MARK: - XML Generation

    private static func versionXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Version VersionId="3.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="version.xsd">
          <DetailedVersion>3.0</DetailedVersion>
        </Version>
        """
    }

    private static func extensionsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <Extensions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="extensions.xsd">
          <TopicTypes>
            <TopicType>Issue</TopicType>
            <TopicType>Clash</TopicType>
            <TopicType>Request</TopicType>
          </TopicTypes>
          <TopicStatuses>
            <TopicStatus>Open</TopicStatus>
            <TopicStatus>In Progress</TopicStatus>
            <TopicStatus>Closed</TopicStatus>
          </TopicStatuses>
          <Priorities>
            <Priority>Low</Priority>
            <Priority>Normal</Priority>
            <Priority>High</Priority>
            <Priority>Critical</Priority>
          </Priorities>
        </Extensions>
        """
    }

    private static func markupXML(issue: BCFIssue, topicGuid: String, viewpointGuid: String, commentGuid: String) -> String {
        let now = iso8601Now()
        let assigneeTag = issue.assignee.isEmpty ? "" : "\n    <AssignedTo>\(esc(issue.assignee))</AssignedTo>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Markup xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="markup.xsd">
          <Topic Guid="\(topicGuid)" TopicType="Issue" TopicStatus="\(esc(issue.status))">
            <Title>\(esc(issue.title))</Title>
            <Description>\(esc(issue.description))</Description>
            <Priority>\(esc(issue.priority))</Priority>\(assigneeTag)
            <CreationDate>\(now)</CreationDate>
            <CreationAuthor>\(esc(issue.author))</CreationAuthor>
          </Topic>
          <Comment Guid="\(commentGuid)">
            <Date>\(now)</Date>
            <Author>\(esc(issue.author))</Author>
            <Comment>\(esc(issue.description))</Comment>
            <Viewpoint Guid="\(viewpointGuid)" />
          </Comment>
          <Viewpoints>
            <ViewPoint Guid="\(viewpointGuid)">
              <Viewpoint>viewpoint.bcfv</Viewpoint>
              <Snapshot>snapshot.jpg</Snapshot>
            </ViewPoint>
          </Viewpoints>
        </Markup>
        """
    }

    private static func viewpointXML(issue: BCFIssue, viewpointGuid: String) -> String {
        // ARKit Y-up to BCF Z-up: BCF.X = AR.X, BCF.Y = -AR.Z, BCF.Z = AR.Y
        let pos = arToBCF(issue.cameraPosition)
        let dir = arToBCF(issue.cameraDirection)
        let up = arToBCF(issue.cameraUp)

        var componentsXML = ""
        if let globalId = issue.selectedGlobalId {
            let ifcType = issue.selectedIfcType ?? "IfcBuildingElementProxy"
            componentsXML = """

              <Components>
                <Selection>
                  <Component IfcGuid="\(esc(globalId))">
                    <OriginatingSystem>IFC-AR</OriginatingSystem>
                    <AuthoringToolId>\(esc(ifcType))</AuthoringToolId>
                  </Component>
                </Selection>
              </Components>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <VisualizationInfo Guid="\(viewpointGuid)" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="visinfo.xsd">
          <PerspectiveCamera>
            <CameraViewPoint>
              <X>\(pos.x)</X>
              <Y>\(pos.y)</Y>
              <Z>\(pos.z)</Z>
            </CameraViewPoint>
            <CameraDirection>
              <X>\(dir.x)</X>
              <Y>\(dir.y)</Y>
              <Z>\(dir.z)</Z>
            </CameraDirection>
            <CameraUpVector>
              <X>\(up.x)</X>
              <Y>\(up.y)</Y>
              <Z>\(up.z)</Z>
            </CameraUpVector>
            <FieldOfView>\(issue.fieldOfView)</FieldOfView>
          </PerspectiveCamera>\(componentsXML)
        </VisualizationInfo>
        """
    }

    // MARK: - Helpers

    private static func arToBCF(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(v.x, -v.z, v.y)
    }

    private static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Minimal ZIP (STORE-only, no compression)

    private static func createZip(from directory: URL, to zipURL: URL) throws {
        var entries: [(path: String, data: Data)] = []
        let basePath = directory.path
        let fm = FileManager.default

        if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                if isDir.boolValue { continue }
                let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
                let data = try Data(contentsOf: fileURL)
                entries.append((relativePath, data))
            }
        }

        var zipData = Data()
        var centralDir = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = crc32(entry.data)

            // Local file header
            var local = Data()
            local.appendU32(0x04034b50)      // signature
            local.appendU16(20)              // version needed
            local.appendU16(0)               // flags
            local.appendU16(0)               // compression: STORE
            local.appendU16(0)               // mod time
            local.appendU16(0)               // mod date
            local.appendU32(crc)             // crc32
            local.appendU32(UInt32(entry.data.count)) // compressed size
            local.appendU32(UInt32(entry.data.count)) // uncompressed size
            local.appendU16(UInt16(nameData.count))   // name length
            local.appendU16(0)               // extra length
            local.append(nameData)
            local.append(entry.data)
            zipData.append(local)

            // Central directory entry
            var cd = Data()
            cd.appendU32(0x02014b50)         // signature
            cd.appendU16(20)                 // version made by
            cd.appendU16(20)                 // version needed
            cd.appendU16(0)                  // flags
            cd.appendU16(0)                  // compression
            cd.appendU16(0)                  // mod time
            cd.appendU16(0)                  // mod date
            cd.appendU32(crc)                // crc32
            cd.appendU32(UInt32(entry.data.count))
            cd.appendU32(UInt32(entry.data.count))
            cd.appendU16(UInt16(nameData.count))
            cd.appendU16(0)                  // extra length
            cd.appendU16(0)                  // comment length
            cd.appendU16(0)                  // disk number
            cd.appendU16(0)                  // internal attrs
            cd.appendU32(0)                  // external attrs
            cd.appendU32(offset)             // local header offset
            cd.append(nameData)
            centralDir.append(cd)

            offset = UInt32(zipData.count)
        }

        let cdOffset = UInt32(zipData.count)
        zipData.append(centralDir)

        // End of central directory
        var eocd = Data()
        eocd.appendU32(0x06054b50)           // signature
        eocd.appendU16(0)                    // disk number
        eocd.appendU16(0)                    // cd disk number
        eocd.appendU16(UInt16(entries.count)) // entries on this disk
        eocd.appendU16(UInt16(entries.count)) // total entries
        eocd.appendU32(UInt32(centralDir.count)) // cd size
        eocd.appendU32(cdOffset)             // cd offset
        eocd.appendU16(0)                    // comment length
        zipData.append(eocd)

        try zipData.write(to: zipURL)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Data helpers for little-endian zip fields

private extension Data {
    mutating func appendU16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func appendU32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
