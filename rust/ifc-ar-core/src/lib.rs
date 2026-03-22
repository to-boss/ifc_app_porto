pub mod color;
pub mod error;
pub mod geometry;
pub mod gltf_export;
pub mod metadata;
pub mod parser;
pub mod types;

use error::IfcArError;
use types::{ElementColor, IfcElement, IfcModel, IfcProperty, MeshData, ModelBounds, SpatialNode, SpatialTree};

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
