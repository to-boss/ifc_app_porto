use ifc_lite_core::{AttributeValue, EntityDecoder};
use rustc_hash::FxHashMap;

use crate::parser::ParsedIfc;
use crate::types::IfcProperty;

/// Extract properties for all elements via IFCRELDEFINESBYPROPERTIES.
///
/// Returns a map from element entity ID to its properties.
pub fn extract_properties(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, Vec<IfcProperty>> {
    let mut result: FxHashMap<u32, Vec<IfcProperty>> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELDEFINESBYPROPERTIES" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // Attribute 4: RelatedObjects (list of element refs)
        let Some(related_attr) = decoded.get(4) else {
            continue;
        };
        let Ok(related_objects) = decoder.resolve_ref_list(related_attr) else {
            continue;
        };
        let element_ids: Vec<u32> = related_objects.iter().map(|e| e.id).collect();

        // Attribute 5: RelatingPropertyDefinition (property set ref)
        let Some(pset_id) = decoded.get_ref(5) else {
            continue;
        };

        let properties = decode_property_set(pset_id, decoder);
        if properties.is_empty() {
            continue;
        }

        for &elem_id in &element_ids {
            result.entry(elem_id).or_default().extend(properties.clone());
        }
    }

    result
}

/// Decode an IFCPROPERTYSET into a list of IfcProperty.
fn decode_property_set(pset_id: u32, decoder: &mut EntityDecoder) -> Vec<IfcProperty> {
    let Ok(pset) = decoder.decode_by_id(pset_id) else {
        return Vec::new();
    };

    // Attribute 2: Name
    let pset_name = pset.get_string(2).map(|s| s.to_string());

    // Attribute 4: HasProperties (list of property refs)
    let Some(props_attr) = pset.get(4) else {
        return Vec::new();
    };
    let Ok(prop_entities) = decoder.resolve_ref_list(props_attr) else {
        return Vec::new();
    };

    let mut properties = Vec::new();

    for prop_entity in &prop_entities {
        // Attribute 0: Name
        let Some(name) = prop_entity.get_string(0) else {
            continue;
        };

        // Attribute 2: NominalValue — extract readable value
        let value = match prop_entity.get(2) {
            Some(attr) => attribute_to_string(attr),
            None => continue,
        };

        if value.is_empty() {
            continue;
        }

        properties.push(IfcProperty {
            name: name.to_string(),
            value,
            property_set: pset_name.clone(),
        });
    }

    properties
}

/// Convert an AttributeValue to a human-readable string.
fn attribute_to_string(attr: &AttributeValue) -> String {
    match attr {
        AttributeValue::String(s) => s.clone(),
        AttributeValue::Integer(i) => i.to_string(),
        AttributeValue::Float(f) => format!("{f}"),
        AttributeValue::Enum(e) => e.trim_matches('.').to_string(),
        AttributeValue::Null => String::new(),
        AttributeValue::Derived => String::new(),
        AttributeValue::EntityRef(_) => String::new(),
        // TypedValue like IFCLABEL('foo') stored as List([String("IFCLABEL"), String("foo")])
        AttributeValue::List(items) if items.len() >= 2 => {
            // First element is the type name, rest are the values
            if matches!(items.first(), Some(AttributeValue::String(_))) {
                // Extract the actual value from the second element
                match items.get(1) {
                    Some(AttributeValue::String(s)) => s.clone(),
                    Some(AttributeValue::Integer(i)) => i.to_string(),
                    Some(AttributeValue::Float(f)) => format!("{f}"),
                    Some(AttributeValue::Enum(e)) => {
                        let trimmed = e.trim_matches('.');
                        match trimmed {
                            "T" => "True".to_string(),
                            "F" => "False".to_string(),
                            _ => trimmed.to_string(),
                        }
                    }
                    _ => String::new(),
                }
            } else {
                String::new()
            }
        }
        AttributeValue::List(_) => String::new(),
    }
}
