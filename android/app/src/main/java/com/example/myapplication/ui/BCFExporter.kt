package com.example.myapplication.ui

import android.content.Context
import com.example.myapplication.ar.BcfIssue
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object BCFExporter {

    /**
     * Exports all BCF issues to a .bcfzip file in the app cache directory.
     * Coordinates are converted from ARCore Y-up to BCF Z-up:
     *   ARCore (x, y, z) -> BCF (x, -z, y)
     */
    fun exportBcf(context: Context, issues: List<BcfIssue>): File {
        val exportDir = File(context.cacheDir, "bcf_export_${System.currentTimeMillis()}")
        exportDir.mkdirs()

        // bcf.version
        val versionFile = File(exportDir, "bcf.version")
        versionFile.writeText(
            """<?xml version="1.0" encoding="UTF-8"?>
<Version xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         VersionId="3.0"
         xsi:noNamespaceSchemaLocation="version.xsd">
  <DetailedVersion>3.0</DetailedVersion>
</Version>"""
        )

        issues.forEach { issue ->
            val issueDir = File(exportDir, issue.id)
            issueDir.mkdirs()

            // Coordinate conversion: ARCore Y-up (x,y,z) -> BCF Z-up (x,-z,y)
            val bcfCamX = issue.cameraX
            val bcfCamY = -issue.cameraZ
            val bcfCamZ = issue.cameraY

            val bcfDirX = issue.dirX
            val bcfDirY = -issue.dirZ
            val bcfDirZ = issue.dirY

            // up vector in ARCore is (0,1,0) -> BCF (0,0,1)
            val bcfUpX = 0f
            val bcfUpY = 0f
            val bcfUpZ = 1f

            val viewpointUuid = java.util.UUID.randomUUID().toString()
            val snapshotFilename = if (issue.snapshotBytes != null) "snapshot.jpg" else null

            // markup.bcf
            val markupContent = buildMarkup(issue, viewpointUuid, snapshotFilename)
            File(issueDir, "markup.bcf").writeText(markupContent)

            // viewpoint.bcfv
            val viewpointContent = buildViewpoint(
                viewpointUuid,
                bcfCamX, bcfCamY, bcfCamZ,
                bcfDirX, bcfDirY, bcfDirZ,
                bcfUpX, bcfUpY, bcfUpZ,
                issue.fovDegrees,
                snapshotFilename
            )
            File(issueDir, "viewpoint.bcfv").writeText(viewpointContent)

            // snapshot
            if (issue.snapshotBytes != null && snapshotFilename != null) {
                File(issueDir, snapshotFilename).writeBytes(issue.snapshotBytes)
            }
        }

        // Zip everything
        val outputFile = File(context.cacheDir, "export_${System.currentTimeMillis()}.bcfzip")
        zipDirectory(exportDir, outputFile)
        exportDir.deleteRecursively()
        return outputFile
    }

    private fun buildMarkup(
        issue: BcfIssue,
        viewpointUuid: String,
        snapshotFilename: String?
    ): String {
        val componentSection = if (!issue.elementGlobalId.isNullOrBlank()) {
            """  <Topic>
    <Components>
      <ViewSetupHints SpacesVisible="false" SpaceBoundariesVisible="false" OpeningsVisible="false"/>
      <Selection>
        <Component IfcGuid="${escapeXml(issue.elementGlobalId)}"/>
      </Selection>
    </Components>
  </Topic>"""
        } else ""

        val snapshotRef = if (snapshotFilename != null) {
            "\n      <Snapshot>$snapshotFilename</Snapshot>"
        } else ""

        return """<?xml version="1.0" encoding="UTF-8"?>
<Markup xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:noNamespaceSchemaLocation="markup.xsd">
  <Topic Guid="${escapeXml(issue.id)}"
         TopicType="Issue"
         TopicStatus="${escapeXml(issue.status)}">
    <Title>${escapeXml(issue.title)}</Title>
    <Priority>${escapeXml(issue.priority)}</Priority>
    <Description>${escapeXml(issue.description)}</Description>
    <AssignedTo>${escapeXml(issue.assignee)}</AssignedTo>
    <Viewpoints>
      <ViewPoint Guid="$viewpointUuid">
        <Viewpoint>viewpoint.bcfv</Viewpoint>$snapshotRef
      </ViewPoint>
    </Viewpoints>
  </Topic>
$componentSection
</Markup>"""
    }

    private fun buildViewpoint(
        guid: String,
        camX: Float, camY: Float, camZ: Float,
        dirX: Float, dirY: Float, dirZ: Float,
        upX: Float, upY: Float, upZ: Float,
        fovDegrees: Float,
        snapshotFilename: String?
    ): String {
        val snapshotElem = if (snapshotFilename != null) {
            "\n  <Snapshot>$snapshotFilename</Snapshot>"
        } else ""

        return """<?xml version="1.0" encoding="UTF-8"?>
<VisualizationInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   Guid="$guid"
                   xsi:noNamespaceSchemaLocation="visinfo.xsd">
  <PerspectiveCamera>
    <CameraViewPoint>
      <X>${camX.formatBcf()}</X>
      <Y>${camY.formatBcf()}</Y>
      <Z>${camZ.formatBcf()}</Z>
    </CameraViewPoint>
    <CameraDirection>
      <X>${dirX.formatBcf()}</X>
      <Y>${dirY.formatBcf()}</Y>
      <Z>${dirZ.formatBcf()}</Z>
    </CameraDirection>
    <CameraUpVector>
      <X>${upX.formatBcf()}</X>
      <Y>${upY.formatBcf()}</Y>
      <Z>${upZ.formatBcf()}</Z>
    </CameraUpVector>
    <FieldOfView>${fovDegrees.formatBcf()}</FieldOfView>
  </PerspectiveCamera>$snapshotElem
</VisualizationInfo>"""
    }

    private fun zipDirectory(sourceDir: File, outputFile: File) {
        ZipOutputStream(FileOutputStream(outputFile)).use { zos ->
            addDirToZip(sourceDir, sourceDir, zos)
        }
    }

    private fun addDirToZip(rootDir: File, currentDir: File, zos: ZipOutputStream) {
        currentDir.listFiles()?.forEach { file ->
            val entryName = rootDir.toURI().relativize(file.toURI()).path
            if (file.isDirectory) {
                addDirToZip(rootDir, file, zos)
            } else {
                val entry = ZipEntry(entryName)
                zos.putNextEntry(entry)
                FileInputStream(file).use { fis ->
                    fis.copyTo(zos)
                }
                zos.closeEntry()
            }
        }
    }

    private fun escapeXml(text: String): String {
        return text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }

    private fun Float.formatBcf(): String = "%.6f".format(this)
}
