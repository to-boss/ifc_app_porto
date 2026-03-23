use crate::error::IfcArError;
use crate::parser;
use crate::geometry;

/// A single edge in the 2D floor plan (wall outline projected to XZ).
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
/// For each wall element, projects vertices onto the XZ plane, computes the
/// convex hull, merges collinear edges, and emits clean outline segments.
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
        // Only walls — skip slabs and everything else
        if !upper.contains("IFCWALL") {
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
            let dominated = xz_points.iter().any(|&(px, pz)| {
                (px - x).abs() < 0.01 && (pz - z).abs() < 0.01
            });
            if !dominated {
                xz_points.push((x, z));
            }
        }

        if xz_points.len() < 3 {
            // Degenerate — fall back to line between the two points
            if xz_points.len() == 2 {
                let dx = xz_points[1].0 - xz_points[0].0;
                let dz = xz_points[1].1 - xz_points[0].1;
                if dx * dx + dz * dz >= 0.0025 {
                    edges.push(FloorPlanEdge {
                        element_id: elem.id,
                        ifc_type: elem.ifc_type.clone(),
                        name: elem.name.clone(),
                        x1: xz_points[0].0,
                        z1: xz_points[0].1,
                        x2: xz_points[1].0,
                        z2: xz_points[1].1,
                    });
                }
            }
            continue;
        }

        // Compute convex hull
        let hull = convex_hull_2d(&mut xz_points);
        if hull.len() < 2 {
            continue;
        }

        // Update bounds from hull vertices
        for &(x, z) in &hull {
            if x < min_x { min_x = x; }
            if x > max_x { max_x = x; }
            if z < min_z { min_z = z; }
            if z > max_z { max_z = z; }
        }

        // Extract edges from hull, merging collinear segments
        let merged = merge_collinear_hull_edges(&hull);

        for (p1, p2) in merged {
            let dx = p2.0 - p1.0;
            let dz = p2.1 - p1.1;
            // Filter very short edges (< 5cm)
            if dx * dx + dz * dz < 0.0025 {
                continue;
            }

            edges.push(FloorPlanEdge {
                element_id: elem.id,
                ifc_type: elem.ifc_type.clone(),
                name: elem.name.clone(),
                x1: p1.0,
                z1: p1.1,
                x2: p2.0,
                z2: p2.1,
            });
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

/// Andrew's monotone chain convex hull algorithm. O(n log n).
/// Returns hull vertices in counter-clockwise order.
fn convex_hull_2d(points: &mut Vec<(f32, f32)>) -> Vec<(f32, f32)> {
    points.sort_by(|a, b| {
        a.0.partial_cmp(&b.0)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
    });
    points.dedup();

    let n = points.len();
    if n < 2 {
        return points.clone();
    }

    let mut hull: Vec<(f32, f32)> = Vec::with_capacity(2 * n);

    // Lower hull
    for &p in points.iter() {
        while hull.len() >= 2 && cross(hull[hull.len() - 2], hull[hull.len() - 1], p) <= 0.0 {
            hull.pop();
        }
        hull.push(p);
    }

    // Upper hull
    let lower_len = hull.len() + 1;
    for &p in points.iter().rev() {
        while hull.len() >= lower_len && cross(hull[hull.len() - 2], hull[hull.len() - 1], p) <= 0.0 {
            hull.pop();
        }
        hull.push(p);
    }

    hull.pop(); // Remove last point (duplicate of first)
    hull
}

/// 2D cross product of vectors OA and OB.
fn cross(o: (f32, f32), a: (f32, f32), b: (f32, f32)) -> f32 {
    (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
}

/// Walk hull vertices and merge adjacent collinear edges.
/// Two edges are collinear if the angle between their direction vectors is < ~3.6°.
fn merge_collinear_hull_edges(hull: &[(f32, f32)]) -> Vec<((f32, f32), (f32, f32))> {
    let n = hull.len();
    if n < 2 {
        return Vec::new();
    }
    if n == 2 {
        return vec![(hull[0], hull[1]), (hull[1], hull[0])];
    }

    // Collect hull edges, then merge collinear adjacent ones
    let mut segments: Vec<((f32, f32), (f32, f32))> = Vec::new();
    for i in 0..n {
        segments.push((hull[i], hull[(i + 1) % n]));
    }

    // Merge pass: repeatedly merge collinear adjacent segments
    let mut merged = true;
    while merged {
        merged = false;
        let mut next_segments: Vec<((f32, f32), (f32, f32))> = Vec::new();
        let mut i = 0;
        while i < segments.len() {
            let (p1, p2) = segments[i];
            if i + 1 < segments.len() {
                let (_q1, q2) = segments[i + 1];
                let dx1 = p2.0 - p1.0;
                let dz1 = p2.1 - p1.1;
                let dx2 = q2.0 - p2.0;
                let dz2 = q2.1 - p2.1;
                let len1 = (dx1 * dx1 + dz1 * dz1).sqrt();
                let len2 = (dx2 * dx2 + dz2 * dz2).sqrt();
                if len1 > 1e-6 && len2 > 1e-6 {
                    let dot = (dx1 * dx2 + dz1 * dz2) / (len1 * len2);
                    if dot > 0.998 {
                        // Merge: skip intermediate point
                        next_segments.push((p1, q2));
                        i += 2;
                        merged = true;
                        continue;
                    }
                }
            }
            next_segments.push((p1, p2));
            i += 1;
        }
        segments = next_segments;
    }

    segments
}
