pub mod color;
pub mod error;
pub mod geometry;
pub mod gltf_export;
pub mod ifc_export;
pub mod metadata;
pub mod parser;
pub mod properties;
pub mod types;

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

/// Input for a fixture to export (UniFFI-compatible dictionary).
pub struct FixtureExportInput {
    pub ifc_data: Vec<u8>,
    pub rel_x: f32,
    pub rel_y: f32,
    pub rel_z: f32,
    pub rotation_y: f32,
}
