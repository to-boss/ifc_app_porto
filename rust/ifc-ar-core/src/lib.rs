pub mod color;
pub mod error;
pub mod geometry;
pub mod gltf_export;
pub mod ifc_export;
pub mod metadata;
pub mod parser;
pub mod properties;
pub mod types;
pub mod wall;

use error::IfcArError;
use types::{
    ElementColor, IfcClassificationInfo, IfcElement, IfcMaterialInfo, IfcMaterialLayer, IfcModel,
    IfcProperty, IfcQuantity, IfcTypeInfo, MeshData, ModelBounds, SpatialNode, SpatialTree,
};

// UniFFI scaffolding
uniffi::include_scaffolding!("ifc_ar_core");

/// Parse an IFC file and export as GLB binary.
///
/// This is the primary entry point for mobile AR apps.
/// Returns a valid GLB (glTF Binary) that can be loaded directly by
/// RealityKit (iOS) or Filament/SceneView (Android).
pub fn parse_and_export_glb(data: Vec<u8>) -> Result<Vec<u8>, IfcArError> {
    let parsed = parser::parse_ifc_bytes(&data)?;
    let (elements, bounds) = geometry::process_geometry(&parsed)?;
    let glb = gltf_export::export_glb(&elements, &bounds)?;
    Ok(glb)
}

/// Parse an IFC file and return the structured model.
///
/// Returns metadata (elements, spatial tree, bounds) without geometry.
/// Useful for displaying element lists, property browsers, etc.
pub fn parse_ifc(data: Vec<u8>) -> Result<IfcModel, IfcArError> {
    let parsed = parser::parse_ifc_bytes(&data)?;
    let (elements, bounds) = geometry::process_geometry(&parsed)?;

    let mut decoder = parser::create_decoder(&parsed);
    let spatial_tree = metadata::build_spatial_tree(&parsed, &mut decoder);

    let ifc_elements: Vec<IfcElement> = elements.iter().map(|e| e.to_ifc_element()).collect();

    Ok(IfcModel {
        elements: ifc_elements,
        spatial_tree,
        bounds,
    })
}

/// Generate a fresh IFC4 file combining room + placed fixtures.
///
/// Parses each IFC through the geometry pipeline, then writes clean
/// tessellated geometry into a new IFC4 file.
pub fn export_combined_ifc(
    room_data: Vec<u8>,
    fixtures: Vec<FixtureExportInput>,
) -> Result<String, IfcArError> {
    let inputs: Vec<ifc_export::FixtureExportInput> = fixtures
        .into_iter()
        .map(|f| ifc_export::FixtureExportInput {
            ifc_data: f.ifc_data,
            rel_x: f.rel_x,
            rel_y: f.rel_y,
            rel_z: f.rel_z,
            rotation_y: f.rotation_y,
        })
        .collect();
    ifc_export::export_combined_ifc(&room_data, &inputs)
}

/// Create a wall mesh from two floor points.
///
/// Generates a box mesh in Y-up AR coordinates.
/// Returns an IfcElement with populated MeshData.
pub fn create_wall_mesh(
    start_x: f32,
    start_z: f32,
    end_x: f32,
    end_z: f32,
    height: f32,
    thickness: f32,
) -> IfcElement {
    wall::create_wall_mesh(start_x, start_z, end_x, end_z, height, thickness)
}

/// Export combined IFC with room, fixtures, and user-created walls.
pub fn export_combined_ifc_with_walls(
    room_data: Vec<u8>,
    fixtures: Vec<FixtureExportInput>,
    walls: Vec<WallExportInput>,
    deleted_element_ids: Vec<u64>,
    moved_elements: Vec<ElementMoveInput>,
) -> Result<String, IfcArError> {
    let fixture_inputs: Vec<ifc_export::FixtureExportInput> = fixtures
        .into_iter()
        .map(|f| ifc_export::FixtureExportInput {
            ifc_data: f.ifc_data,
            rel_x: f.rel_x,
            rel_y: f.rel_y,
            rel_z: f.rel_z,
            rotation_y: f.rotation_y,
        })
        .collect();
    let wall_inputs: Vec<ifc_export::WallExportInput> = walls
        .into_iter()
        .map(|w| ifc_export::WallExportInput {
            positions: w.positions,
            normals: w.normals,
            indices: w.indices,
            rel_x: w.rel_x,
            rel_y: w.rel_y,
            rel_z: w.rel_z,
            height: w.height,
            thickness: w.thickness,
            length: w.length,
        })
        .collect();
    let move_inputs: Vec<ifc_export::ElementMoveInput> = moved_elements
        .into_iter()
        .map(|m| ifc_export::ElementMoveInput {
            element_id: m.element_id,
            offset_x: m.offset_x,
            offset_y: m.offset_y,
            offset_z: m.offset_z,
        })
        .collect();
    ifc_export::export_combined_ifc_with_walls(&room_data, &fixture_inputs, &wall_inputs, &deleted_element_ids, &move_inputs)
}

/// Input for a moved element (UniFFI-compatible dictionary).
pub struct ElementMoveInput {
    pub element_id: u64,
    pub offset_x: f32,
    pub offset_y: f32,
    pub offset_z: f32,
}

/// Input for a user-created wall to export (UniFFI-compatible dictionary).
pub struct WallExportInput {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub indices: Vec<u32>,
    pub rel_x: f32,
    pub rel_y: f32,
    pub rel_z: f32,
    pub height: f32,
    pub thickness: f32,
    pub length: f32,
}

/// Input for a fixture to export (UniFFI-compatible dictionary).
pub struct FixtureExportInput {
    pub ifc_data: Vec<u8>,
    pub rel_x: f32,
    pub rel_y: f32,
    pub rel_z: f32,
    pub rotation_y: f32,
}
