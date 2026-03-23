use ifc_lite_core::{has_geometry_by_name, EntityScanner};
use ifc_lite_geometry::{calculate_normals, GeometryRouter};
use rustc_hash::FxHashMap;

use crate::color::{build_style_index, default_color_for_type};
use crate::error::IfcArError;
use crate::parser::ParsedIfc;
use crate::types::{ElementColor, InternalElement, ModelBounds};

/// Process all geometry-bearing entities in the parsed IFC file.
///
/// Returns a list of IfcElements with mesh data and colors, plus model bounds.
pub fn process_geometry(
    parsed: &ParsedIfc,
) -> Result<(Vec<InternalElement>, ModelBounds), IfcArError> {
    let mut decoder = crate::parser::create_decoder(parsed);

    // Build style index for color lookup
    let style_map = build_style_index(parsed, &mut decoder);

    // Extract properties and metadata for all elements
    let property_map = crate::properties::extract_properties(parsed, &mut decoder);
    let quantity_map = crate::properties::extract_quantities(parsed, &mut decoder);
    let material_map = crate::properties::extract_materials(parsed, &mut decoder);
    let type_map = crate::properties::extract_types(parsed, &mut decoder);
    let classification_map = crate::properties::extract_classifications(parsed, &mut decoder);

    // Create geometry router with automatic unit detection
    let router = GeometryRouter::with_units(&parsed.content, &mut decoder);

    // Build void index: maps host element IDs → their opening element IDs
    // by scanning IfcRelVoidsElement relationships
    let mut void_map: FxHashMap<u32, Vec<u32>> = FxHashMap::default();
    {
        let mut scanner = EntityScanner::new(&parsed.content);
        while let Some((id, type_name, start, end)) = scanner.next_entity() {
            if type_name == "IFCRELVOIDSELEMENT" {
                if let Ok(entity) = decoder.decode_at_with_id(id, start, end) {
                    if let (Some(host_id), Some(opening_id)) =
                        (entity.get_ref(4), entity.get_ref(5))
                    {
                        void_map.entry(host_id).or_default().push(opening_id);
                    }
                }
            }
        }
    }

    let mut elements = Vec::new();
    let mut bounds = ModelBounds::default();

    // Process only geometry-bearing entities, skipping non-renderable types:
    // - IFCOPENINGELEMENT/IFCOPENINGSTANDARDCASE: void shapes used only for CSG subtraction
    // - IFCSPACE: invisible room volumes
    for scanned in parsed.all_entities.iter().filter(|e| {
        has_geometry_by_name(&e.ifc_type)
            && !matches!(
                e.ifc_type.as_str(),
                "IFCOPENINGELEMENT" | "IFCOPENINGSTANDARDCASE" | "IFCSPACE"
            )
    }) {
        let Ok(entity) = decoder.decode_by_id(scanned.id) else {
            continue;
        };

        // Use GeometryRouter to process the element's representation chain.
        // For elements with openings, use CSG void subtraction to cut holes.
        let has_openings = void_map.contains_key(&scanned.id);
        let mesh = if has_openings {
            match router.process_element_with_voids(&entity, &mut decoder, &void_map) {
                Ok(mut mesh) if !mesh.is_empty() => {
                    if mesh.normals.len() != mesh.positions.len() {
                        calculate_normals(&mut mesh);
                    }
                    z_up_to_y_up(&mut mesh.positions);
                    z_up_to_y_up(&mut mesh.normals);
                    bounds.extend_from_positions(&mesh.positions);
                    Some(mesh)
                }
                _ => {
                    // Fallback: render without void subtraction rather than skipping
                    match router.process_element(&entity, &mut decoder) {
                        Ok(mesh) if !mesh.is_empty() => {
                            let mut mesh = mesh;
                            z_up_to_y_up(&mut mesh.positions);
                            z_up_to_y_up(&mut mesh.normals);
                            bounds.extend_from_positions(&mesh.positions);
                            Some(mesh)
                        }
                        _ => None,
                    }
                }
            }
        } else {
            match router.process_element(&entity, &mut decoder) {
                Ok(mesh) if !mesh.is_empty() => {
                    let mut mesh = mesh;
                    z_up_to_y_up(&mut mesh.positions);
                    z_up_to_y_up(&mut mesh.normals);
                    bounds.extend_from_positions(&mesh.positions);
                    Some(mesh)
                }
                _ => None,
            }
        };

        // Resolve color: style map → default by type
        let color = resolve_color(scanned.id, &scanned.ifc_type, &style_map);

        // Extract element attributes
        let name = entity.get_string(2).map(|s| s.to_string());
        let global_id = entity.get_string(0).map(|s| s.to_string());
        let description = entity.get_string(3).map(|s| s.to_string());
        let object_type = entity.get_string(4).map(|s| s.to_string());
        let tag = entity.get_string(7).map(|s| s.to_string());
        let predefined_type = match entity.get(8) {
            Some(ifc_lite_core::AttributeValue::Enum(e)) => Some(e.clone()),
            _ => entity.get(9).and_then(|a| match a {
                ifc_lite_core::AttributeValue::Enum(e) => Some(e.clone()),
                _ => None,
            }),
        };

        let properties = property_map
            .get(&scanned.id)
            .cloned()
            .unwrap_or_default();
        let quantities = quantity_map
            .get(&scanned.id)
            .cloned()
            .unwrap_or_default();
        let material = material_map.get(&scanned.id).cloned();
        let type_info = type_map.get(&scanned.id).cloned();
        let classification = classification_map.get(&scanned.id).cloned();

        elements.push(InternalElement {
            id: scanned.id as u64,
            ifc_type: scanned.ifc_type.clone(),
            name,
            global_id,
            description,
            object_type,
            tag,
            predefined_type,
            geometry: mesh,
            color,
            properties,
            quantities,
            material,
            type_info,
            classification,
        });
    }

    // Center model at origin
    if bounds.diagonal > 0.0 {
        let center = bounds.center();
        for element in &mut elements {
            if let Some(ref mut mesh) = element.geometry {
                center_positions(&mut mesh.positions, &center);
            }
        }
        // Recalculate bounds after centering
        bounds = ModelBounds::default();
        for element in &elements {
            if let Some(ref mesh) = element.geometry {
                bounds.extend_from_positions(&mesh.positions);
            }
        }
    }

    Ok((elements, bounds))
}

/// Transform positions/normals from IFC Z-up to glTF/AR Y-up coordinate system.
fn z_up_to_y_up(data: &mut [f32]) {
    for chunk in data.chunks_exact_mut(3) {
        let y = chunk[1];
        chunk[1] = chunk[2]; // new Y = old Z (up)
        chunk[2] = -y;       // new Z = -old Y (backward)
    }
}

/// Subtract the center offset from all vertex positions.
fn center_positions(positions: &mut [f32], center: &[f32; 3]) {
    for chunk in positions.chunks_exact_mut(3) {
        chunk[0] -= center[0];
        chunk[1] -= center[1];
        chunk[2] -= center[2];
    }
}

/// Resolve color for an entity: style map first, then default by type.
fn resolve_color(
    entity_id: u32,
    ifc_type: &str,
    style_map: &FxHashMap<u32, [f32; 4]>,
) -> ElementColor {
    if let Some(color) = style_map.get(&entity_id) {
        ElementColor {
            r: color[0],
            g: color[1],
            b: color[2],
            a: color[3],
        }
    } else {
        let default = default_color_for_type(ifc_type);
        ElementColor {
            r: default[0],
            g: default[1],
            b: default[2],
            a: default[3],
        }
    }
}
