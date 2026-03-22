use ifc_lite_core::{AttributeValue, EntityDecoder, IfcType};
use rustc_hash::FxHashMap;

use crate::parser::ParsedIfc;
use crate::types::{IfcClassificationInfo, IfcMaterialInfo, IfcMaterialLayer, IfcProperty, IfcQuantity, IfcTypeInfo};

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

        // Check if target is IFCPROPERTYSET (skip IFCELEMENTQUANTITY here)
        let Ok(pset_entity) = decoder.decode_by_id(pset_id) else {
            continue;
        };
        if pset_entity.ifc_type != IfcType::IfcPropertySet {
            continue;
        }

        let properties = decode_property_set_from(pset_entity, decoder);
        if properties.is_empty() {
            continue;
        }

        for &elem_id in &element_ids {
            result.entry(elem_id).or_default().extend(properties.clone());
        }
    }

    result
}

/// Extract quantities for all elements via IFCRELDEFINESBYPROPERTIES → IFCELEMENTQUANTITY.
pub fn extract_quantities(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, Vec<IfcQuantity>> {
    let mut result: FxHashMap<u32, Vec<IfcQuantity>> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELDEFINESBYPROPERTIES" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        let Some(related_attr) = decoded.get(4) else {
            continue;
        };
        let Ok(related_objects) = decoder.resolve_ref_list(related_attr) else {
            continue;
        };
        let element_ids: Vec<u32> = related_objects.iter().map(|e| e.id).collect();

        let Some(qset_id) = decoded.get_ref(5) else {
            continue;
        };

        let Ok(qset_entity) = decoder.decode_by_id(qset_id) else {
            continue;
        };
        if qset_entity.ifc_type != IfcType::IfcElementQuantity {
            continue;
        }

        let quantities = decode_element_quantity(qset_entity, decoder);
        if quantities.is_empty() {
            continue;
        }

        for &elem_id in &element_ids {
            result.entry(elem_id).or_default().extend(quantities.clone());
        }
    }

    result
}

/// Extract material assignments via IFCRELASSOCIATESMATERIAL.
pub fn extract_materials(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, IfcMaterialInfo> {
    let mut result: FxHashMap<u32, IfcMaterialInfo> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELASSOCIATESMATERIAL" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // Attribute 4: RelatedObjects
        let Some(related_attr) = decoded.get(4) else {
            continue;
        };
        let Ok(related_objects) = decoder.resolve_ref_list(related_attr) else {
            continue;
        };
        let element_ids: Vec<u32> = related_objects.iter().map(|e| e.id).collect();

        // Attribute 5: RelatingMaterial
        let Some(mat_id) = decoded.get_ref(5) else {
            continue;
        };

        let Some(mat_info) = decode_material(mat_id, decoder) else {
            continue;
        };

        for &elem_id in &element_ids {
            result.insert(elem_id, mat_info.clone());
        }
    }

    result
}

/// Extract type definitions via IFCRELDEFINESBYTYPE.
pub fn extract_types(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, IfcTypeInfo> {
    let mut result: FxHashMap<u32, IfcTypeInfo> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELDEFINESBYTYPE" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // Attribute 4: RelatedObjects
        let Some(related_attr) = decoded.get(4) else {
            continue;
        };
        let Ok(related_objects) = decoder.resolve_ref_list(related_attr) else {
            continue;
        };
        let element_ids: Vec<u32> = related_objects.iter().map(|e| e.id).collect();

        // Attribute 5: RelatingType
        let Some(type_id) = decoded.get_ref(5) else {
            continue;
        };

        let Ok(type_entity) = decoder.decode_by_id(type_id) else {
            continue;
        };

        let type_info = IfcTypeInfo {
            ifc_type: format!("{:?}", type_entity.ifc_type),
            name: type_entity.get_string(2).map(|s| s.to_string()),
            predefined_type: extract_enum_attr(&type_entity, 9)
                .or_else(|| extract_enum_attr(&type_entity, 8)),
        };

        for &elem_id in &element_ids {
            result.insert(elem_id, type_info.clone());
        }
    }

    result
}

/// Extract classifications via IFCRELASSOCIATESCLASSIFICATION.
pub fn extract_classifications(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, IfcClassificationInfo> {
    let mut result: FxHashMap<u32, IfcClassificationInfo> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELASSOCIATESCLASSIFICATION" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // Attribute 4: RelatedObjects
        let Some(related_attr) = decoded.get(4) else {
            continue;
        };
        let Ok(related_objects) = decoder.resolve_ref_list(related_attr) else {
            continue;
        };
        let element_ids: Vec<u32> = related_objects.iter().map(|e| e.id).collect();

        // Attribute 5: RelatingClassification (IFCCLASSIFICATIONREFERENCE)
        let Some(classref_id) = decoded.get_ref(5) else {
            continue;
        };

        let Ok(classref) = decoder.decode_by_id(classref_id) else {
            continue;
        };

        // IFCCLASSIFICATIONREFERENCE: Location(0), Identification(1), Name(2), ReferencedSource(3)
        let ref_name = classref.get_string(1)
            .or_else(|| classref.get_string(2))
            .unwrap_or("")
            .to_string();

        // Resolve the IFCCLASSIFICATION from ReferencedSource (attr 3)
        let (system_name, system_source) = if let Some(class_id) = classref.get_ref(3) {
            if let Ok(classification) = decoder.decode_by_id(class_id) {
                // IFCCLASSIFICATION: Source(0), Edition(1), EditionDate(2), Name(3)
                let name = classification.get_string(3).unwrap_or("").to_string();
                let source = classification.get_string(0).map(|s| s.to_string());
                (name, source)
            } else {
                (String::new(), None)
            }
        } else {
            (String::new(), None)
        };

        if ref_name.is_empty() && system_name.is_empty() {
            continue;
        }

        let info = IfcClassificationInfo {
            name: ref_name,
            system_name,
            system_source,
        };

        for &elem_id in &element_ids {
            result.insert(elem_id, info.clone());
        }
    }

    result
}

// --- Internal helpers ---

/// Decode an IFCPROPERTYSET (already decoded) into a list of IfcProperty.
fn decode_property_set_from(pset: ifc_lite_core::DecodedEntity, decoder: &mut EntityDecoder) -> Vec<IfcProperty> {
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

/// Decode an IFCELEMENTQUANTITY into a list of IfcQuantity.
fn decode_element_quantity(qset: ifc_lite_core::DecodedEntity, decoder: &mut EntityDecoder) -> Vec<IfcQuantity> {
    // IFCELEMENTQUANTITY: GlobalId(0), OwnerHistory(1), Name(2), Description(3), MethodOfMeasurement(4), Quantities(5)
    let qset_name = qset.get_string(2).map(|s| s.to_string());

    let Some(quantities_attr) = qset.get(5) else {
        return Vec::new();
    };
    let Ok(quantity_entities) = decoder.resolve_ref_list(quantities_attr) else {
        return Vec::new();
    };

    let mut quantities = Vec::new();

    for q in &quantity_entities {
        let Some(name) = q.get_string(0) else {
            continue;
        };

        // All IFCQUANTITY* types have the value at attribute 3
        let Some(value) = q.get_float(3) else {
            continue;
        };

        let quantity_type = match q.ifc_type {
            IfcType::IfcQuantityLength => "Length",
            IfcType::IfcQuantityArea => "Area",
            IfcType::IfcQuantityVolume => "Volume",
            IfcType::IfcQuantityCount => "Count",
            IfcType::IfcQuantityWeight => "Weight",
            _ => continue,
        };

        quantities.push(IfcQuantity {
            name: name.to_string(),
            value,
            quantity_type: quantity_type.to_string(),
            quantity_set: qset_name.clone(),
        });
    }

    quantities
}

/// Decode a material reference (IFCMATERIAL, IFCMATERIALLAYERSET, IFCMATERIALLAYERSETUSAGE).
fn decode_material(mat_id: u32, decoder: &mut EntityDecoder) -> Option<IfcMaterialInfo> {
    let entity = decoder.decode_by_id(mat_id).ok()?;

    match entity.ifc_type {
        IfcType::IfcMaterial => {
            // IFCMATERIAL: Name(0), Description(1), Category(2)
            let name = entity.get_string(0)?.to_string();
            let category = entity.get_string(2).map(|s| s.to_string());
            Some(IfcMaterialInfo { name, category, layers: Vec::new() })
        }
        IfcType::IfcMaterialLayerSetUsage => {
            // IFCMATERIALLAYERSETUSAGE: ForLayerSet(0), ...
            let layer_set_id = entity.get_ref(0)?;
            decode_material_layer_set(layer_set_id, decoder)
        }
        IfcType::IfcMaterialLayerSet => {
            decode_material_layer_set(mat_id, decoder)
        }
        IfcType::IfcMaterialConstituentSet => {
            // IFCMATERIALCONSTITUENTSET: Name(0), Description(1), MaterialConstituents(2)
            let name = entity.get_string(0).unwrap_or("").to_string();
            Some(IfcMaterialInfo { name, category: None, layers: Vec::new() })
        }
        _ => None,
    }
}

fn decode_material_layer_set(id: u32, decoder: &mut EntityDecoder) -> Option<IfcMaterialInfo> {
    let entity = decoder.decode_by_id(id).ok()?;
    // IFCMATERIALLAYERSET: MaterialLayers(0), LayerSetName(1)
    let name = entity.get_string(1).unwrap_or("").to_string();

    let mut layers = Vec::new();
    if let Some(layers_attr) = entity.get(0) {
        if let Ok(layer_entities) = decoder.resolve_ref_list(layers_attr) {
            for layer in &layer_entities {
                // IFCMATERIALLAYER: Material(0), LayerThickness(1)
                let material_name = if let Some(mat_ref) = layer.get_ref(0) {
                    decoder.decode_by_id(mat_ref).ok()
                        .and_then(|m| m.get_string(0).map(|s| s.to_string()))
                        .unwrap_or_default()
                } else {
                    String::new()
                };
                let thickness = layer.get_float(1);
                layers.push(IfcMaterialLayer { material_name, thickness });
            }
        }
    }

    Some(IfcMaterialInfo { name, category: None, layers })
}

/// Extract an enum attribute (like PredefinedType) as a string.
fn extract_enum_attr(entity: &ifc_lite_core::DecodedEntity, index: usize) -> Option<String> {
    match entity.get(index)? {
        AttributeValue::Enum(e) => Some(e.clone()),
        _ => None,
    }
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
