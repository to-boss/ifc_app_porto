/// A parsed IFC model with elements, spatial tree, and bounds.
pub struct IfcModel {
    pub elements: Vec<IfcElement>,
    pub spatial_tree: SpatialTree,
    pub bounds: ModelBounds,
}

/// A single IFC building element with optional geometry.
pub struct IfcElement {
    pub id: u64,
    pub ifc_type: String,
    pub name: Option<String>,
    pub global_id: Option<String>,
    pub description: Option<String>,
    pub object_type: Option<String>,
    pub tag: Option<String>,
    pub predefined_type: Option<String>,
    pub color: ElementColor,
    pub geometry: Option<MeshData>,
    pub properties: Vec<IfcProperty>,
    pub quantities: Vec<IfcQuantity>,
    pub material: Option<IfcMaterialInfo>,
    pub type_info: Option<IfcTypeInfo>,
    pub classification: Option<IfcClassificationInfo>,
}

/// Internal element type used during processing.
/// Uses ifc-lite-geometry's Mesh directly.
pub struct InternalElement {
    pub id: u64,
    pub ifc_type: String,
    pub name: Option<String>,
    pub global_id: Option<String>,
    pub description: Option<String>,
    pub object_type: Option<String>,
    pub tag: Option<String>,
    pub predefined_type: Option<String>,
    pub geometry: Option<ifc_lite_geometry::Mesh>,
    pub color: ElementColor,
    pub properties: Vec<IfcProperty>,
    pub quantities: Vec<IfcQuantity>,
    pub material: Option<IfcMaterialInfo>,
    pub type_info: Option<IfcTypeInfo>,
    pub classification: Option<IfcClassificationInfo>,
}

impl InternalElement {
    pub fn to_ifc_element(&self) -> IfcElement {
        IfcElement {
            id: self.id,
            ifc_type: self.ifc_type.clone(),
            name: self.name.clone(),
            global_id: self.global_id.clone(),
            description: self.description.clone(),
            object_type: self.object_type.clone(),
            tag: self.tag.clone(),
            predefined_type: self.predefined_type.clone(),
            color: self.color,
            geometry: self.geometry.as_ref().map(|m| MeshData {
                positions: m.positions.clone(),
                normals: m.normals.clone(),
                indices: m.indices.clone(),
            }),
            properties: self.properties.clone(),
            quantities: self.quantities.clone(),
            material: self.material.clone(),
            type_info: self.type_info.clone(),
            classification: self.classification.clone(),
        }
    }
}

/// Triangle mesh data exposed through UniFFI.
#[derive(Clone, Default)]
pub struct MeshData {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub indices: Vec<u32>,
}

/// RGBA color for an element.
#[derive(Clone, Copy)]
pub struct ElementColor {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Default for ElementColor {
    fn default() -> Self {
        Self {
            r: 0.8,
            g: 0.8,
            b: 0.8,
            a: 1.0,
        }
    }
}

/// A property key-value pair, optionally grouped in a property set.
#[derive(Clone)]
pub struct IfcProperty {
    pub name: String,
    pub value: String,
    pub property_set: Option<String>,
}

/// A quantity value from an IFCELEMENTQUANTITY.
#[derive(Clone)]
pub struct IfcQuantity {
    pub name: String,
    pub value: f64,
    /// "Length", "Area", "Volume", "Count", "Weight"
    pub quantity_type: String,
    pub quantity_set: Option<String>,
}

/// Material information for an element.
#[derive(Clone)]
pub struct IfcMaterialInfo {
    pub name: String,
    pub category: Option<String>,
    pub layers: Vec<IfcMaterialLayer>,
}

/// A single layer in a material layer set.
#[derive(Clone)]
pub struct IfcMaterialLayer {
    pub material_name: String,
    pub thickness: Option<f64>,
}

/// Type product information from IFCRELDEFINESBYTYPE.
#[derive(Clone)]
pub struct IfcTypeInfo {
    pub ifc_type: String,
    pub name: Option<String>,
    pub predefined_type: Option<String>,
}

/// Classification reference from IFCRELASSOCIATESCLASSIFICATION.
#[derive(Clone)]
pub struct IfcClassificationInfo {
    pub name: String,
    pub system_name: String,
    pub system_source: Option<String>,
}

/// The spatial hierarchy of the IFC model.
pub struct SpatialTree {
    pub nodes: Vec<SpatialNode>,
}

/// A node in the spatial hierarchy (project, site, building, storey).
pub struct SpatialNode {
    pub id: u64,
    pub ifc_type: String,
    pub name: Option<String>,
    pub children: Vec<u64>,
}

/// Axis-aligned bounding box of the model.
pub struct ModelBounds {
    pub min_point: Vec<f32>,
    pub max_point: Vec<f32>,
    pub diagonal: f32,
}

impl Default for ModelBounds {
    fn default() -> Self {
        Self {
            min_point: vec![f32::MAX; 3],
            max_point: vec![f32::MIN; 3],
            diagonal: 0.0,
        }
    }
}

impl ModelBounds {
    pub fn extend_from_positions(&mut self, positions: &[f32]) {
        for chunk in positions.chunks_exact(3) {
            for i in 0..3 {
                self.min_point[i] = self.min_point[i].min(chunk[i]);
                self.max_point[i] = self.max_point[i].max(chunk[i]);
            }
        }
        self.recompute_diagonal();
    }

    pub fn center(&self) -> [f32; 3] {
        [
            (self.min_point[0] + self.max_point[0]) / 2.0,
            (self.min_point[1] + self.max_point[1]) / 2.0,
            (self.min_point[2] + self.max_point[2]) / 2.0,
        ]
    }

    fn recompute_diagonal(&mut self) {
        let dx = self.max_point[0] - self.min_point[0];
        let dy = self.max_point[1] - self.min_point[1];
        let dz = self.max_point[2] - self.min_point[2];
        self.diagonal = (dx * dx + dy * dy + dz * dz).sqrt();
    }
}
