use crate::error::IfcArError;
use crate::parser;
use crate::geometry;

/// A single edge in the 2D floor plan (wall centerline projected to XZ).
pub struct FloorPlanEdge {
    pub element_id: u64,
    pub ifc_type: String,
    pub name: Option<String>,
    pub x1: f32,
    pub z1: f32,
    pub x2: f32,
    pub z2: f32,
}

/// 2D floor plan with wall edges and bounds.
pub struct FloorPlan {
    pub edges: Vec<FloorPlanEdge>,
    pub min_x: f32,
    pub min_z: f32,
    pub max_x: f32,
    pub max_z: f32,
}

/// Extract 2D floor plan edges from an IFC file.
///
/// For each wall element, projects vertices onto the XZ plane and finds
/// the two furthest-apart points (the wall's run axis).
pub fn extract_floor_plan(data: &[u8]) -> Result<FloorPlan, IfcArError> {
    let parsed = parser::parse_ifc_bytes(data)?;
    let (elements, _bounds) = geometry::process_geometry(&parsed)?;

    let mut edges = Vec::new();
    let mut min_x = f32::MAX;
    let mut min_z = f32::MAX;
    let mut max_x = f32::MIN;
    let mut max_z = f32::MIN;

    for elem in &elements {
        let upper = elem.ifc_type.to_uppercase();
        if !upper.contains("IFCWALL") && !upper.contains("IFCSLAB") {
            continue;
        }
        let mesh = match &elem.geometry {
            Some(m) if !m.positions.is_empty() => m,
            _ => continue,
        };

        // Project vertices to XZ plane, deduplicate with small tolerance
        let mut xz_points: Vec<(f32, f32)> = Vec::new();
        for chunk in mesh.positions.chunks_exact(3) {
            let x = chunk[0];
            let z = chunk[2];
            // Skip near-duplicates
            let dominated = xz_points.iter().any(|&(px, pz)| {
                (px - x).abs() < 0.01 && (pz - z).abs() < 0.01
            });
            if !dominated {
                xz_points.push((x, z));
            }
        }

        if xz_points.len() < 2 {
            continue;
        }

        // Find the two points furthest apart in XZ
        let mut best_dist_sq = 0.0f32;
        let mut best_p1 = xz_points[0];
        let mut best_p2 = xz_points[1];

        for i in 0..xz_points.len() {
            for j in (i + 1)..xz_points.len() {
                let dx = xz_points[j].0 - xz_points[i].0;
                let dz = xz_points[j].1 - xz_points[i].1;
                let d = dx * dx + dz * dz;
                if d > best_dist_sq {
                    best_dist_sq = d;
                    best_p1 = xz_points[i];
                    best_p2 = xz_points[j];
                }
            }
        }

        if best_dist_sq < 0.01 {
            continue;
        }

        edges.push(FloorPlanEdge {
            element_id: elem.id,
            ifc_type: elem.ifc_type.clone(),
            name: elem.name.clone(),
            x1: best_p1.0,
            z1: best_p1.1,
            x2: best_p2.0,
            z2: best_p2.1,
        });

        for &(x, z) in &[best_p1, best_p2] {
            if x < min_x { min_x = x; }
            if x > max_x { max_x = x; }
            if z < min_z { min_z = z; }
            if z > max_z { max_z = z; }
        }
    }

    // Handle empty case
    if edges.is_empty() {
        min_x = 0.0;
        min_z = 0.0;
        max_x = 0.0;
        max_z = 0.0;
    }

    Ok(FloorPlan {
        edges,
        min_x,
        min_z,
        max_x,
        max_z,
    })
}
