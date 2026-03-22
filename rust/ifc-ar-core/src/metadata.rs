use ifc_lite_core::EntityDecoder;

use crate::parser::ParsedIfc;
use crate::types::{SpatialNode, SpatialTree};

/// Build the spatial hierarchy: IfcProject → IfcSite → IfcBuilding → IfcBuildingStorey.
///
/// Walks IfcRelAggregates relationships to discover parent-child connections.
pub fn build_spatial_tree(parsed: &ParsedIfc, decoder: &mut EntityDecoder) -> SpatialTree {
    let mut nodes = Vec::new();

    // Find all IfcRelAggregates to map parent → children
    let mut children_map: std::collections::HashMap<u32, Vec<u32>> =
        std::collections::HashMap::new();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCRELAGGREGATES" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // IfcRelAggregates(GlobalId, OwnerHistory, Name, Description, RelatingObject, RelatedObjects)
        let relating_ref = decoded.get_ref(4);
        if relating_ref.is_none() {
            continue;
        }
        let parent_id = relating_ref.unwrap();

        // RelatedObjects is a list of refs (attribute 5)
        if let Ok(children) = decoder.resolve_ref_list(decoded.get(5).unwrap()) {
            let child_ids: Vec<u32> = children.iter().map(|c| c.id).collect();
            children_map
                .entry(parent_id)
                .or_default()
                .extend(child_ids);
        }
    }

    // Collect spatial structure elements
    let spatial_types = [
        "IFCPROJECT",
        "IFCSITE",
        "IFCBUILDING",
        "IFCBUILDINGSTOREY",
    ];

    for entity in &parsed.all_entities {
        if !spatial_types.contains(&entity.ifc_type.as_str()) {
            continue;
        }

        let name = decoder
            .decode_by_id(entity.id)
            .ok()
            .and_then(|d| d.get_string(2).map(|s| s.to_string()));

        let children = children_map
            .get(&entity.id)
            .cloned()
            .unwrap_or_default()
            .into_iter()
            .map(|id| id as u64)
            .collect();

        nodes.push(SpatialNode {
            id: entity.id as u64,
            ifc_type: entity.ifc_type.clone(),
            name,
            children,
        });
    }

    SpatialTree { nodes }
}
