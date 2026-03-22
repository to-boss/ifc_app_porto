use std::sync::Arc;

use ifc_lite_core::{build_entity_index, EntityDecoder, EntityIndex, EntityScanner};

use crate::error::IfcArError;

/// Scanned entity info: (express_id, ifc_type_name, byte_start, byte_end).
pub struct ScannedEntity {
    pub id: u32,
    pub ifc_type: String,
    pub start: usize,
    pub end: usize,
}

/// Result of parsing an IFC file: the content, index, and scanned entities.
pub struct ParsedIfc {
    pub content: String,
    pub entity_index: Arc<EntityIndex>,
    pub geometry_entities: Vec<ScannedEntity>,
    pub all_entities: Vec<ScannedEntity>,
}

/// Parse IFC file bytes into a structured result with entity index.
pub fn parse_ifc_bytes(data: &[u8]) -> Result<ParsedIfc, IfcArError> {
    let content = std::str::from_utf8(data)
        .map_err(|e| IfcArError::parse(format!("Invalid UTF-8: {e}")))?
        .to_string();

    parse_ifc_content(content)
}

/// Parse IFC file content string.
pub fn parse_ifc_content(content: String) -> Result<ParsedIfc, IfcArError> {
    if content.is_empty() {
        return Err(IfcArError::invalid_input("Empty IFC file"));
    }

    // Build entity index for O(1) lookups
    let entity_index = Arc::new(build_entity_index(&content));

    // Scan all entities to categorize them
    let mut scanner = EntityScanner::new(&content);
    let mut geometry_entities = Vec::new();
    let mut all_entities = Vec::new();

    while let Some((id, type_str, start, end)) = scanner.next_entity() {
        let ifc_type = type_str.to_string();

        all_entities.push(ScannedEntity {
            id,
            ifc_type: ifc_type.clone(),
            start,
            end,
        });

        // Collect entities that have geometric representations
        if is_geometry_bearing_type(&ifc_type) {
            geometry_entities.push(ScannedEntity {
                id,
                ifc_type,
                start,
                end,
            });
        }
    }

    Ok(ParsedIfc {
        content,
        entity_index,
        geometry_entities,
        all_entities,
    })
}

/// Create a decoder from parsed IFC data.
pub fn create_decoder<'a>(parsed: &'a ParsedIfc) -> EntityDecoder<'a> {
    EntityDecoder::with_arc_index(&parsed.content, Arc::clone(&parsed.entity_index))
}

/// Extract a string attribute from a decoded entity at the given index.
pub fn get_entity_name(
    decoder: &mut EntityDecoder,
    entity_id: u32,
) -> Option<String> {
    let entity = decoder.decode_by_id(entity_id).ok()?;
    // IFC entities typically have Name at attribute index 2
    entity.get_string(2).map(|s| s.to_string())
}

/// Extract the GlobalId (attribute index 0) from an entity.
pub fn get_entity_global_id(
    decoder: &mut EntityDecoder,
    entity_id: u32,
) -> Option<String> {
    let entity = decoder.decode_by_id(entity_id).ok()?;
    entity.get_string(0).map(|s| s.to_string())
}

/// Check if an IFC type typically carries geometry.
fn is_geometry_bearing_type(ifc_type: &str) -> bool {
    matches!(
        ifc_type,
        "IFCWALL"
            | "IFCWALLSTANDARDCASE"
            | "IFCSLAB"
            | "IFCBEAM"
            | "IFCCOLUMN"
            | "IFCWINDOW"
            | "IFCDOOR"
            | "IFCROOF"
            | "IFCSTAIR"
            | "IFCSTAIRFLIGHT"
            | "IFCRAMP"
            | "IFCRAMPFLIGHT"
            | "IFCRAILING"
            | "IFCPLATE"
            | "IFCMEMBER"
            | "IFCCURTAINWALL"
            | "IFCFOOTING"
            | "IFCPILE"
            | "IFCBUILDINGELEMENTPROXY"
            | "IFCFURNISHINGELEMENT"
            | "IFCFLOWSEGMENT"
            | "IFCFLOWTERMINAL"
            | "IFCFLOWFITTING"
            | "IFCDISTRIBUTIONELEMENT"
            | "IFCOPENINGELEMENT"
            | "IFCSPACE"
            | "IFCCOVERING"
    )
}
