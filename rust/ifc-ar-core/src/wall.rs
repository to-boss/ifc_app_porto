use crate::types::{ElementColor, IfcElement, MeshData};

/// Generate a wall mesh from two floor points.
///
/// Coordinates are in AR Y-up space (Y=up, X=right, Z=backward).
/// The wall runs from (start_x, 0, start_z) to (end_x, 0, end_z),
/// extends upward by `height`, and has `thickness` perpendicular to its direction.
pub fn create_wall_mesh(
    start_x: f32,
    start_z: f32,
    end_x: f32,
    end_z: f32,
    height: f32,
    thickness: f32,
) -> IfcElement {
    let dx = end_x - start_x;
    let dz = end_z - start_z;
    let length = (dx * dx + dz * dz).sqrt();

    // Degenerate case
    if length < 1e-6 {
        return empty_wall();
    }

    // Normalized direction in XZ plane
    let dir_x = dx / length;
    let dir_z = dz / length;

    // Perpendicular (rotated 90 degrees in XZ), scaled by half thickness
    let half = thickness / 2.0;
    let perp_x = -dir_z * half;
    let perp_z = dir_x * half;

    // 8 corner positions: 4 bottom (Y=0), 4 top (Y=height)
    // s0,s1 = start face corners, e0,e1 = end face corners
    // 0 = -perp side, 1 = +perp side
    let s0 = [start_x - perp_x, 0.0, start_z - perp_z];
    let s1 = [start_x + perp_x, 0.0, start_z + perp_z];
    let e0 = [end_x - perp_x, 0.0, end_z - perp_z];
    let e1 = [end_x + perp_x, 0.0, end_z + perp_z];

    let s0t = [s0[0], height, s0[2]];
    let s1t = [s1[0], height, s1[2]];
    let e0t = [e0[0], height, e0[2]];
    let e1t = [e1[0], height, e1[2]];

    // 6 faces, 4 vertices each = 24 vertices
    // Each face has its own vertices for correct flat normals
    let mut positions: Vec<f32> = Vec::with_capacity(72);
    let mut normals: Vec<f32> = Vec::with_capacity(72);
    let mut indices: Vec<u32> = Vec::with_capacity(36);

    let n_front = [perp_x / half, 0.0, perp_z / half]; // +perp direction
    let n_back = [-n_front[0], 0.0, -n_front[2]];
    let n_top = [0.0f32, 1.0, 0.0];
    let n_bottom = [0.0f32, -1.0, 0.0];
    let n_start = [-dir_x, 0.0, -dir_z]; // -direction
    let n_end = [dir_x, 0.0, dir_z]; // +direction

    // Helper: add a quad (4 verts, 2 tris)
    // Vertices should be wound counter-clockwise when viewed from the normal direction
    let mut add_quad = |v0: [f32; 3], v1: [f32; 3], v2: [f32; 3], v3: [f32; 3], n: [f32; 3]| {
        let base = (positions.len() / 3) as u32;
        for v in &[v0, v1, v2, v3] {
            positions.extend_from_slice(v);
            normals.extend_from_slice(&n);
        }
        // Two triangles: 0-1-2, 0-2-3
        indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    };

    // Front face (+perp): s1, e1, e1t, s1t (viewed from +perp direction)
    add_quad(s1, e1, e1t, s1t, n_front);

    // Back face (-perp): e0, s0, s0t, e0t (viewed from -perp direction)
    add_quad(e0, s0, s0t, e0t, n_back);

    // Top face (+Y): s1t, e1t, e0t, s0t
    add_quad(s1t, e1t, e0t, s0t, n_top);

    // Bottom face (-Y): s0, e0, e1, s1
    add_quad(s0, e0, e1, s1, n_bottom);

    // Start cap (-dir): s0, s1, s1t, s0t
    add_quad(s0, s1, s1t, s0t, n_start);

    // End cap (+dir): e1, e0, e0t, e1t
    add_quad(e1, e0, e0t, e1t, n_end);

    IfcElement {
        id: 0,
        ifc_type: "IFCWALL".to_string(),
        name: Some("User Wall".to_string()),
        global_id: None,
        description: None,
        object_type: None,
        tag: None,
        predefined_type: Some(".STANDARD.".to_string()),
        color: ElementColor {
            r: 0.85,
            g: 0.83,
            b: 0.80,
            a: 1.0,
        },
        geometry: Some(MeshData {
            positions,
            normals,
            indices,
        }),
        properties: vec![],
        quantities: vec![],
        material: None,
        type_info: None,
        classification: None,
    }
}

fn empty_wall() -> IfcElement {
    IfcElement {
        id: 0,
        ifc_type: "IFCWALL".to_string(),
        name: Some("User Wall".to_string()),
        global_id: None,
        description: None,
        object_type: None,
        tag: None,
        predefined_type: Some(".STANDARD.".to_string()),
        color: ElementColor {
            r: 0.85,
            g: 0.83,
            b: 0.80,
            a: 1.0,
        },
        geometry: Some(MeshData::default()),
        properties: vec![],
        quantities: vec![],
        material: None,
        type_info: None,
        classification: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_wall() {
        let wall = create_wall_mesh(0.0, 0.0, 2.0, 0.0, 2.5, 0.2);
        let geo = wall.geometry.unwrap();
        assert_eq!(geo.positions.len(), 72); // 24 verts * 3
        assert_eq!(geo.normals.len(), 72);
        assert_eq!(geo.indices.len(), 36); // 12 tris * 3
        assert_eq!(wall.ifc_type, "IFCWALL");
    }

    #[test]
    fn test_degenerate_wall() {
        let wall = create_wall_mesh(1.0, 1.0, 1.0, 1.0, 2.5, 0.2);
        let geo = wall.geometry.unwrap();
        assert!(geo.positions.is_empty());
    }
}
