use std::fmt::Write;

use crate::error::IfcArError;
use crate::geometry::process_geometry;
use crate::parser::parse_ifc_bytes;
use crate::types::InternalElement;

/// Input for a fixture to be included in the export.
pub struct FixtureExportInput {
    pub ifc_data: Vec<u8>,
    pub rel_x: f32,
    pub rel_y: f32,
    pub rel_z: f32,
    pub rotation_y: f32,
}

/// Generate a fresh IFC4 file from parsed room + fixture geometry.
///
/// Parses each IFC through our pipeline, then writes a clean IFC4 file
/// with tessellated geometry (IFCTRIANGULATEDFACESET).
pub fn export_combined_ifc(
    room_data: &[u8],
    fixtures: &[FixtureExportInput],
) -> Result<String, IfcArError> {
    // Parse room
    let room_parsed = parse_ifc_bytes(room_data)?;
    let (room_elements, _) = process_geometry(&room_parsed)?;

    // Parse each fixture
    let mut fixture_groups: Vec<(Vec<InternalElement>, f32, f32, f32, f32)> = Vec::new();
    for f in fixtures {
        let parsed = parse_ifc_bytes(&f.ifc_data)?;
        let (elements, _) = process_geometry(&parsed)?;
        fixture_groups.push((elements, f.rel_x, f.rel_y, f.rel_z, f.rotation_y));
    }

    // Generate IFC4 text
    let mut out = String::with_capacity(512_000);
    let mut id = IdCounter::new();

    // Header
    writeln!(out, "ISO-10303-21;").unwrap();
    writeln!(out, "HEADER;").unwrap();
    writeln!(out, "FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');").unwrap();
    writeln!(out, "FILE_NAME('AR-Export.ifc','2026-03-22',(''),(''),'','IFC-AR Viewer','');").unwrap();
    writeln!(out, "FILE_SCHEMA(('IFC4'));").unwrap();
    writeln!(out, "ENDSEC;").unwrap();
    writeln!(out, "DATA;").unwrap();

    // Infrastructure
    let owner = id.next(); // #1
    let app = id.next();   // #2
    let person = id.next();
    let org = id.next();
    let person_org = id.next();
    let ctx = id.next();
    let sub_ctx = id.next();
    let units = id.next();
    let length_unit = id.next();
    let area_unit = id.next();
    let volume_unit = id.next();
    let angle_unit = id.next();
    let project = id.next();
    let site = id.next();
    let building = id.next();
    let storey = id.next();
    let origin_pt = id.next();
    let origin_axis = id.next();
    let site_placement = id.next();
    let building_placement = id.next();
    let storey_placement = id.next();
    let agg1 = id.next();
    let agg2 = id.next();
    let agg3 = id.next();

    writeln!(out, "#{person}=IFCPERSON($,$,'',$,$,$,$,$);").unwrap();
    writeln!(out, "#{org}=IFCORGANIZATION($,'',$,$,$);").unwrap();
    writeln!(out, "#{person_org}=IFCPERSONANDORGANIZATION(#{person},#{org},$);").unwrap();
    writeln!(out, "#{app}=IFCAPPLICATION(#{org},'1.0','IFC-AR Viewer','IFCAR');").unwrap();
    writeln!(out, "#{owner}=IFCOWNERHISTORY(#{person_org},#{app},$,.NOCHANGE.,$,$,$,0);").unwrap();

    writeln!(out, "#{origin_pt}=IFCCARTESIANPOINT((0.,0.,0.));").unwrap();
    writeln!(out, "#{origin_axis}=IFCAXIS2PLACEMENT3D(#{origin_pt},$,$);").unwrap();
    writeln!(out, "#{ctx}=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#{origin_axis},$);").unwrap();
    writeln!(out, "#{sub_ctx}=IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#{ctx},$,.MODEL_VIEW.,$);").unwrap();

    writeln!(out, "#{length_unit}=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);").unwrap();
    writeln!(out, "#{area_unit}=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);").unwrap();
    writeln!(out, "#{volume_unit}=IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);").unwrap();
    writeln!(out, "#{angle_unit}=IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.);").unwrap();
    writeln!(out, "#{units}=IFCUNITASSIGNMENT((#{length_unit},#{area_unit},#{volume_unit},#{angle_unit}));").unwrap();

    writeln!(out, "#{site_placement}=IFCLOCALPLACEMENT($,#{origin_axis});").unwrap();
    writeln!(out, "#{building_placement}=IFCLOCALPLACEMENT(#{site_placement},#{origin_axis});").unwrap();
    writeln!(out, "#{storey_placement}=IFCLOCALPLACEMENT(#{building_placement},#{origin_axis});").unwrap();

    writeln!(out, "#{project}=IFCPROJECT('1000000000000000000000',#{owner},'AR Export',$,$,$,$,(#{ctx}),#{units});").unwrap();
    writeln!(out, "#{site}=IFCSITE('1000000000000000000001',#{owner},'Site',$,$,#{site_placement},$,$,.ELEMENT.,$,$,$,$,$);").unwrap();
    writeln!(out, "#{building}=IFCBUILDING('1000000000000000000002',#{owner},'Building',$,$,#{building_placement},$,$,.ELEMENT.,$,$,$);").unwrap();
    writeln!(out, "#{storey}=IFCBUILDINGSTOREY('1000000000000000000003',#{owner},'Level 0',$,$,#{storey_placement},$,$,.ELEMENT.,0.);").unwrap();

    writeln!(out, "#{agg1}=IFCRELAGGREGATES('2000000000000000000001',#{owner},$,$,#{project},(#{site}));").unwrap();
    writeln!(out, "#{agg2}=IFCRELAGGREGATES('2000000000000000000002',#{owner},$,$,#{site},(#{building}));").unwrap();
    writeln!(out, "#{agg3}=IFCRELAGGREGATES('2000000000000000000003',#{owner},$,$,#{building},(#{storey}));").unwrap();

    // Write room elements (at origin)
    let mut all_product_ids: Vec<u32> = Vec::new();

    for element in &room_elements {
        if let Some(ref mesh) = element.geometry {
            if mesh.positions.is_empty() || mesh.indices.is_empty() {
                continue;
            }
            if let Some(product_id) = write_element(
                &mut out,
                &mut id,
                element,
                mesh,
                0.0, 0.0, 0.0, 0.0, // no offset for room
                owner,
                sub_ctx,
                storey_placement,
            ) {
                all_product_ids.push(product_id);
            }
        }
    }

    // Write fixture elements (with AR offset)
    for (elements, rel_x, rel_y, rel_z, rot_y) in &fixture_groups {
        for element in elements {
            if let Some(ref mesh) = element.geometry {
                if mesh.positions.is_empty() || mesh.indices.is_empty() {
                    continue;
                }
                if let Some(product_id) = write_element(
                    &mut out,
                    &mut id,
                    element,
                    mesh,
                    *rel_x, *rel_y, *rel_z, *rot_y,
                    owner,
                    sub_ctx,
                    storey_placement,
                ) {
                    all_product_ids.push(product_id);
                }
            }
        }
    }

    // Spatial containment
    if !all_product_ids.is_empty() {
        let rel_id = id.next();
        let products: String = all_product_ids
            .iter()
            .map(|id| format!("#{id}"))
            .collect::<Vec<_>>()
            .join(",");
        writeln!(
            out,
            "#{rel_id}=IFCRELCONTAINEDINSPATIALSTRUCTURE('3000000000000000000001',#{owner},$,$,({products}),#{storey});"
        ).unwrap();
    }

    writeln!(out, "ENDSEC;").unwrap();
    writeln!(out, "END-ISO-10303-21;").unwrap();

    Ok(out)
}

/// Write a single element's geometry + product entity. Returns the product entity ID.
fn write_element(
    out: &mut String,
    id: &mut IdCounter,
    element: &InternalElement,
    mesh: &ifc_lite_geometry::Mesh,
    offset_x: f32,
    offset_y: f32,
    offset_z: f32,
    rotation_y: f32,
    owner: u32,
    sub_ctx: u32,
    storey_placement: u32,
) -> Option<u32> {
    let positions = &mesh.positions;
    let indices = &mesh.indices;

    if positions.len() < 9 || indices.len() < 3 {
        return None;
    }

    let vert_count = positions.len() / 3;
    let tri_count = indices.len() / 3;

    // Convert positions: AR Y-up → IFC Z-up, apply offset + rotation
    let cos_r = rotation_y.cos();
    let sin_r = rotation_y.sin();

    // Write IFCCARTESIANPOINTLIST3D
    let pointlist_id = id.next();
    write!(out, "#{pointlist_id}=IFCCARTESIANPOINTLIST3D((").unwrap();
    for i in 0..vert_count {
        let ax = positions[i * 3];
        let ay = positions[i * 3 + 1];
        let az = positions[i * 3 + 2];

        // Apply rotation around Y (AR space)
        let rx = cos_r * ax - sin_r * az;
        let rz = sin_r * ax + cos_r * az;

        // Apply offset (AR space)
        let ax2 = rx + offset_x;
        let ay2 = ay + offset_y;
        let az2 = rz + offset_z;

        // Convert AR Y-up → IFC Z-up: ifc_x = ar_x, ifc_y = -ar_z, ifc_z = ar_y
        let ix = ax2 as f64;
        let iy = -az2 as f64;
        let iz = ay2 as f64;

        if i > 0 {
            write!(out, ",").unwrap();
        }
        write!(out, "({ix},{iy},{iz})").unwrap();
    }
    writeln!(out, "));").unwrap();

    // Write IFCTRIANGULATEDFACESET (IFC uses 1-based indices)
    let faceset_id = id.next();
    write!(out, "#{faceset_id}=IFCTRIANGULATEDFACESET(#{pointlist_id},$,.T.,(").unwrap();
    for t in 0..tri_count {
        let i0 = indices[t * 3] + 1;     // 1-based
        let i1 = indices[t * 3 + 1] + 1;
        let i2 = indices[t * 3 + 2] + 1;
        if t > 0 {
            write!(out, ",").unwrap();
        }
        write!(out, "({i0},{i1},{i2})").unwrap();
    }
    writeln!(out, "),$);").unwrap();

    // Shape representation
    let shaperep_id = id.next();
    writeln!(out, "#{shaperep_id}=IFCSHAPEREPRESENTATION(#{sub_ctx},'Body','Tessellation',(#{faceset_id}));").unwrap();

    let prodshape_id = id.next();
    writeln!(out, "#{prodshape_id}=IFCPRODUCTDEFINITIONSHAPE($,$,(#{shaperep_id}));").unwrap();

    // Placement (at storey level, identity transform — geometry already positioned)
    let placement_id = id.next();
    let placement_pt = id.next();
    let placement_axis = id.next();
    writeln!(out, "#{placement_pt}=IFCCARTESIANPOINT((0.,0.,0.));").unwrap();
    writeln!(out, "#{placement_axis}=IFCAXIS2PLACEMENT3D(#{placement_pt},$,$);").unwrap();
    writeln!(out, "#{placement_id}=IFCLOCALPLACEMENT(#{storey_placement},#{placement_axis});").unwrap();

    // Product entity
    let product_id = id.next();
    let name = element.name.as_deref().unwrap_or("");
    let escaped_name = name.replace('\'', "''");

    // Map IFC type to a valid product type
    let ifc_type = map_to_product_type(&element.ifc_type);

    // Generate a simple GUID
    let guid = format!("E{:021}", product_id);

    writeln!(
        out,
        "#{product_id}={ifc_type}('{guid}',#{owner},'{escaped_name}',$,$,#{placement_id},#{prodshape_id},$);"
    ).unwrap();

    // Color via IFCSTYLEDITEM
    let c = &element.color;
    let color_id = id.next();
    let rendering_id = id.next();
    let surface_style_id = id.next();
    let pres_style_id = id.next();
    let styled_item_id = id.next();

    writeln!(out, "#{color_id}=IFCCOLOURRGB($,{},{},{});", c.r as f64, c.g as f64, c.b as f64).unwrap();
    writeln!(out, "#{rendering_id}=IFCSURFACESTYLERENDERING(#{color_id},$,$,$,$,$,$,$,.FLAT.);").unwrap();
    writeln!(out, "#{surface_style_id}=IFCSURFACESTYLE('',.BOTH.,(#{rendering_id}));").unwrap();
    writeln!(out, "#{pres_style_id}=IFCPRESENTATIONSTYLEASSIGNMENT((#{surface_style_id}));").unwrap();
    writeln!(out, "#{styled_item_id}=IFCSTYLEDITEM(#{faceset_id},(#{pres_style_id}),$);").unwrap();

    Some(product_id)
}

/// Map our parsed IFC type to a valid IfcProduct subtype for export.
/// Falls back to IFCBUILDINGELEMENTPROXY for unknown types.
fn map_to_product_type(ifc_type: &str) -> &'static str {
    match ifc_type.to_uppercase().as_str() {
        "IFCWALL" | "IFCWALLSTANDARDCASE" => "IFCWALL",
        "IFCDOOR" => "IFCDOOR",
        "IFCWINDOW" => "IFCWINDOW",
        "IFCSLAB" => "IFCSLAB",
        "IFCCOLUMN" => "IFCCOLUMN",
        "IFCBEAM" => "IFCBEAM",
        "IFCROOF" => "IFCROOF",
        "IFCSTAIR" => "IFCSTAIR",
        "IFCRAILING" => "IFCRAILING",
        "IFCPLATE" => "IFCPLATE",
        "IFCMEMBER" => "IFCMEMBER",
        "IFCCOVERING" => "IFCCOVERING",
        "IFCFURNISHINGELEMENT" => "IFCFURNISHINGELEMENT",
        "IFCSANITARYTERMINAL" => "IFCSANITARYTERMINAL",
        "IFCFLOWSEGMENT" => "IFCFLOWSEGMENT",
        "IFCFLOWTERMINAL" => "IFCFLOWTERMINAL",
        "IFCOPENINGELEMENT" => "IFCOPENINGELEMENT",
        "IFCSPACE" => "IFCSPACE",
        _ => "IFCBUILDINGELEMENTPROXY",
    }
}

/// Simple sequential ID counter.
struct IdCounter {
    current: u32,
}

impl IdCounter {
    fn new() -> Self {
        Self { current: 0 }
    }
    fn next(&mut self) -> u32 {
        self.current += 1;
        self.current
    }
}
