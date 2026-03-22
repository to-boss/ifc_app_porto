use std::sync::Arc;

use ifc_lite_core::{build_entity_index, EntityDecoder, EntityIndex, EntityScanner};

use crate::error::IfcArError;

pub struct ScannedEntity {
    pub id: u32,
    pub ifc_type: String,
}

/// Result of parsing an IFC file: the content, index, and scanned entities.
pub struct ParsedIfc {
    pub content: String,
    pub entity_index: Arc<EntityIndex>,
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
    let mut all_entities = Vec::new();

    while let Some((id, type_str, _start, _end)) = scanner.next_entity() {
        all_entities.push(ScannedEntity {
            id,
            ifc_type: type_str.to_string(),
        });
    }

    Ok(ParsedIfc {
        content,
        entity_index,
        all_entities,
    })
}

/// Create a decoder from parsed IFC data.
pub fn create_decoder<'a>(parsed: &'a ParsedIfc) -> EntityDecoder<'a> {
    EntityDecoder::with_arc_index(&parsed.content, Arc::clone(&parsed.entity_index))
}


