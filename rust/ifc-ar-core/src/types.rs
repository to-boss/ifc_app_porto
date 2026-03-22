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
    pub color: ElementColor,
    pub geometry: Option<MeshData>,
    pub properties: Vec<IfcProperty>,
}

/// Internal element type used during processing.
/// Uses ifc-lite-geometry's Mesh directly.
pub struct InternalElement {
    pub id: u64,
    pub ifc_type: String,
    pub name: Option<String>,
    pub global_id: Option<String>,
    pub geometry: Option<ifc_lite_geometry::Mesh>,
    pub color: ElementColor,
    pub properties: Vec<IfcProperty>,
}

impl InternalElement {
    pub fn to_ifc_element(&self) -> IfcElement {
        IfcElement {
            id: self.id,
            ifc_type: self.ifc_type.clone(),
            name: self.name.clone(),
            global_id: self.global_id.clone(),
            color: self.color,
            geometry: self.geometry.as_ref().map(|m| MeshData {
                positions: m.positions.clone(),
                normals: m.normals.clone(),
                indices: m.indices.clone(),
            }),
            properties: self.properties.clone(),
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
