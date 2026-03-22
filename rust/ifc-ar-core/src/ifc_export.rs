use std::collections::HashMap;
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

/// Input for a user-created wall to be included in the export.
pub struct WallExportInput {
    pub positions: Vec<f32>,
    pub normals: Vec<f32>,
    pub indices: Vec<u32>,
    pub rel_x: f32,
    pub rel_y: f32,
    pub rel_z: f32,
    pub height: f32,
    pub thickness: f32,
    pub length: f32,
}

/// Generate a fresh IFC4 file from parsed room + fixture geometry.
///
/// Parses each IFC through our pipeline, then writes a clean IFC4 file
/// with tessellated geometry (IFCTRIANGULATEDFACESET) and all metadata
/// (properties, quantities, materials, types, classifications).
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
    let mut shared = SharedEntities::new();

    // Header
    writeln!(out, "ISO-10303-21;").unwrap();
    writeln!(out, "HEADER;").unwrap();
    writeln!(out, "FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');").unwrap();
    writeln!(out, "FILE_NAME('AR-Export.ifc','2026-03-22',(''),(''),'','IFC-AR Viewer','');").unwrap();
    writeln!(out, "FILE_SCHEMA(('IFC4'));").unwrap();
    writeln!(out, "ENDSEC;").unwrap();
    writeln!(out, "DATA;").unwrap();

    // Infrastructure
    let owner = id.next();
    let app = id.next();
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
                &mut out, &mut id, &mut shared,
                element, mesh,
                0.0, 0.0, 0.0, 0.0,
                owner, sub_ctx, storey_placement,
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
                    &mut out, &mut id, &mut shared,
                    element, mesh,
                    *rel_x, *rel_y, *rel_z, *rot_y,
                    owner, sub_ctx, storey_placement,
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

/// Generate a fresh IFC4 file from parsed room + fixtures + user-created walls.
pub fn export_combined_ifc_with_walls(
    room_data: &[u8],
    fixtures: &[FixtureExportInput],
    walls: &[WallExportInput],
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
    let mut shared = SharedEntities::new();

    // Header
    writeln!(out, "ISO-10303-21;").unwrap();
    writeln!(out, "HEADER;").unwrap();
    writeln!(out, "FILE_DESCRIPTION(('ViewDefinition [ReferenceView_V1.2]'),'2;1');").unwrap();
    writeln!(out, "FILE_NAME('AR-Export.ifc','2026-03-22',(''),(''),'','IFC-AR Viewer','');").unwrap();
    writeln!(out, "FILE_SCHEMA(('IFC4'));").unwrap();
    writeln!(out, "ENDSEC;").unwrap();
    writeln!(out, "DATA;").unwrap();

    // Infrastructure (same as export_combined_ifc)
    let owner = id.next();
    let app = id.next();
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

    // Write room elements
    let mut all_product_ids: Vec<u32> = Vec::new();

    for element in &room_elements {
        if let Some(ref mesh) = element.geometry {
            if mesh.positions.is_empty() || mesh.indices.is_empty() {
                continue;
            }
            if let Some(product_id) = write_element(
                &mut out, &mut id, &mut shared,
                element, mesh,
                0.0, 0.0, 0.0, 0.0,
                owner, sub_ctx, storey_placement,
            ) {
                all_product_ids.push(product_id);
            }
        }
    }

    // Write fixture elements
    for (elements, rel_x, rel_y, rel_z, rot_y) in &fixture_groups {
        for element in elements {
            if let Some(ref mesh) = element.geometry {
                if mesh.positions.is_empty() || mesh.indices.is_empty() {
                    continue;
                }
                if let Some(product_id) = write_element(
                    &mut out, &mut id, &mut shared,
                    element, mesh,
                    *rel_x, *rel_y, *rel_z, *rot_y,
                    owner, sub_ctx, storey_placement,
                ) {
                    all_product_ids.push(product_id);
                }
            }
        }
    }

    // Write user-created walls
    for wall in walls {
        if wall.positions.is_empty() || wall.indices.is_empty() {
            continue;
        }
        if let Some(product_id) = write_wall_element(
            &mut out, &mut id,
            wall,
            owner, sub_ctx, storey_placement,
        ) {
            all_product_ids.push(product_id);
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

/// Write a user-created wall element from raw mesh data.
fn write_wall_element(
    out: &mut String,
    id: &mut IdCounter,
    wall: &WallExportInput,
    owner: u32,
    sub_ctx: u32,
    storey_placement: u32,
) -> Option<u32> {
    let positions = &wall.positions;
    let indices = &wall.indices;

    if positions.len() < 9 || indices.len() < 3 {
        return None;
    }

    let vert_count = positions.len() / 3;
    let tri_count = indices.len() / 3;

    // Write IFCCARTESIANPOINTLIST3D with AR Y-up → IFC Z-up conversion + offset
    let pointlist_id = id.next();
    write!(out, "#{pointlist_id}=IFCCARTESIANPOINTLIST3D((").unwrap();
    for i in 0..vert_count {
        let ax = positions[i * 3] + wall.rel_x;
        let ay = positions[i * 3 + 1] + wall.rel_y;
        let az = positions[i * 3 + 2] + wall.rel_z;

        // AR Y-up → IFC Z-up: ifc_x = ar_x, ifc_y = -ar_z, ifc_z = ar_y
        let ix = ax as f64;
        let iy = -az as f64;
        let iz = ay as f64;

        if i > 0 {
            write!(out, ",").unwrap();
        }
        write!(out, "({ix},{iy},{iz})").unwrap();
    }
    writeln!(out, "));").unwrap();

    // Write IFCTRIANGULATEDFACESET
    let faceset_id = id.next();
    write!(out, "#{faceset_id}=IFCTRIANGULATEDFACESET(#{pointlist_id},$,.T.,(").unwrap();
    for t in 0..tri_count {
        let i0 = indices[t * 3] + 1;
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

    // Placement
    let placement_id = id.next();
    let placement_pt = id.next();
    let placement_axis = id.next();
    writeln!(out, "#{placement_pt}=IFCCARTESIANPOINT((0.,0.,0.));").unwrap();
    writeln!(out, "#{placement_axis}=IFCAXIS2PLACEMENT3D(#{placement_pt},$,$);").unwrap();
    writeln!(out, "#{placement_id}=IFCLOCALPLACEMENT(#{storey_placement},#{placement_axis});").unwrap();

    // IFCWALL product
    let product_id = id.next();
    let guid = format!("W{:021}", product_id);
    writeln!(
        out,
        "#{product_id}=IFCWALL('{guid}',#{owner},'User Wall',$,$,#{placement_id},#{prodshape_id},$,.STANDARD.);"
    ).unwrap();

    // Wall color style
    let color_id = id.next();
    let rendering_id = id.next();
    let surface_style_id = id.next();
    let pres_style_id = id.next();
    let styled_item_id = id.next();

    writeln!(out, "#{color_id}=IFCCOLOURRGB($,0.85,0.83,0.8);").unwrap();
    writeln!(out, "#{rendering_id}=IFCSURFACESTYLERENDERING(#{color_id},$,$,$,$,$,$,$,.FLAT.);").unwrap();
    writeln!(out, "#{surface_style_id}=IFCSURFACESTYLE('',.BOTH.,(#{rendering_id}));").unwrap();
    writeln!(out, "#{pres_style_id}=IFCPRESENTATIONSTYLEASSIGNMENT((#{surface_style_id}));").unwrap();
    writeln!(out, "#{styled_item_id}=IFCSTYLEDITEM(#{faceset_id},(#{pres_style_id}),$);").unwrap();

    // Material: Concrete
    let mat_id = id.next();
    writeln!(out, "#{mat_id}=IFCMATERIAL('Concrete',$,'Concrete');").unwrap();
    let mat_rel_id = id.next();
    let mat_rel_guid = format!("M{:021}", mat_rel_id);
    writeln!(out, "#{mat_rel_id}=IFCRELASSOCIATESMATERIAL('{mat_rel_guid}',#{owner},$,$,(#{product_id}),#{mat_id});").unwrap();

    // Base quantities
    let height = wall.height as f64;
    let thickness = wall.thickness as f64;
    let length = wall.length as f64;
    let area = length * height;
    let volume = area * thickness;

    let q_length_id = id.next();
    writeln!(out, "#{q_length_id}=IFCQUANTITYLENGTH('Length',$,$,{length},$);").unwrap();
    let q_height_id = id.next();
    writeln!(out, "#{q_height_id}=IFCQUANTITYLENGTH('Height',$,$,{height},$);").unwrap();
    let q_width_id = id.next();
    writeln!(out, "#{q_width_id}=IFCQUANTITYLENGTH('Width',$,$,{thickness},$);").unwrap();
    let q_area_id = id.next();
    writeln!(out, "#{q_area_id}=IFCQUANTITYAREA('GrossSideArea',$,$,{area},$);").unwrap();
    let q_volume_id = id.next();
    writeln!(out, "#{q_volume_id}=IFCQUANTITYVOLUME('GrossVolume',$,$,{volume},$);").unwrap();

    let qset_id = id.next();
    let qset_guid = format!("Q{:021}", qset_id);
    writeln!(out, "#{qset_id}=IFCELEMENTQUANTITY('{qset_guid}',#{owner},'Qto_WallBaseQuantities',$,$,(#{q_length_id},#{q_height_id},#{q_width_id},#{q_area_id},#{q_volume_id}));").unwrap();
    let qrel_id = id.next();
    let qrel_guid = format!("D{:021}", qrel_id);
    writeln!(out, "#{qrel_id}=IFCRELDEFINESBYPROPERTIES('{qrel_guid}',#{owner},$,$,(#{product_id}),#{qset_id});").unwrap();

    // Wall type
    let type_id = id.next();
    let type_guid = format!("T{:021}", type_id);
    writeln!(out, "#{type_id}=IFCWALLTYPE('{type_guid}',#{owner},'Standard Wall',$,$,$,$,$,$,.STANDARD.);").unwrap();
    let type_rel_id = id.next();
    let type_rel_guid = format!("Y{:021}", type_rel_id);
    writeln!(out, "#{type_rel_id}=IFCRELDEFINESBYTYPE('{type_rel_guid}',#{owner},$,$,(#{product_id}),#{type_id});").unwrap();

    Some(product_id)
}

/// Write a single element's geometry, product entity, and all metadata.
/// Returns the product entity ID.
fn write_element(
    out: &mut String,
    id: &mut IdCounter,
    shared: &mut SharedEntities,
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
        let i0 = indices[t * 3] + 1;
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

    // Placement
    let placement_id = id.next();
    let placement_pt = id.next();
    let placement_axis = id.next();
    writeln!(out, "#{placement_pt}=IFCCARTESIANPOINT((0.,0.,0.));").unwrap();
    writeln!(out, "#{placement_axis}=IFCAXIS2PLACEMENT3D(#{placement_pt},$,$);").unwrap();
    writeln!(out, "#{placement_id}=IFCLOCALPLACEMENT(#{storey_placement},#{placement_axis});").unwrap();

    // Product entity with all attributes
    let product_id = id.next();
    let ifc_type = map_to_product_type(&element.ifc_type);
    let guid = format!("E{:021}", product_id);

    let name = ifc_str_or_null(&element.name);
    let description = ifc_str_or_null(&element.description);
    let object_type = ifc_str_or_null(&element.object_type);
    let tag = ifc_str_or_null(&element.tag);

    // Some types need PredefinedType as last attribute
    let needs_predefined = needs_predefined_type(ifc_type);
    let predefined = if needs_predefined {
        element.predefined_type.as_deref()
            .or_else(|| element.type_info.as_ref().and_then(|t| t.predefined_type.as_deref()))
            .map(|p| {
                // Ensure it has dots
                if p.starts_with('.') { p.to_string() } else { format!(".{p}.") }
            })
    } else {
        None
    };

    if needs_predefined {
        let pred_str = predefined.as_deref().unwrap_or("$");
        writeln!(
            out,
            "#{product_id}={ifc_type}('{guid}',#{owner},{name},{description},{object_type},#{placement_id},#{prodshape_id},{tag},{pred_str});"
        ).unwrap();
    } else {
        writeln!(
            out,
            "#{product_id}={ifc_type}('{guid}',#{owner},{name},{description},{object_type},#{placement_id},#{prodshape_id},{tag});"
        ).unwrap();
    }

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

    // --- Properties ---
    write_properties(out, id, &element.properties, product_id, owner);

    // --- Quantities ---
    write_quantities(out, id, &element.quantities, product_id, owner);

    // --- Material ---
    if let Some(ref mat) = element.material {
        write_material(out, id, shared, mat, product_id, owner);
    }

    // --- Type ---
    if let Some(ref type_info) = element.type_info {
        write_type(out, id, shared, type_info, product_id, owner);
    }

    // --- Classification ---
    if let Some(ref classification) = element.classification {
        write_classification(out, id, shared, classification, product_id, owner);
    }

    Some(product_id)
}

/// Write IFCPROPERTYSET + IFCPROPERTYSINGLEVALUE + IFCRELDEFINESBYPROPERTIES.
fn write_properties(
    out: &mut String,
    id: &mut IdCounter,
    properties: &[crate::types::IfcProperty],
    product_id: u32,
    owner: u32,
) {
    if properties.is_empty() {
        return;
    }

    // Group by property set
    let mut groups: HashMap<String, Vec<&crate::types::IfcProperty>> = HashMap::new();
    for prop in properties {
        let key = prop.property_set.as_deref().unwrap_or("Properties").to_string();
        groups.entry(key).or_default().push(prop);
    }

    for (pset_name, props) in &groups {
        let mut prop_ids = Vec::new();

        for prop in props {
            let prop_id = id.next();
            let name = escape_ifc(&prop.name);
            let value = escape_ifc(&prop.value);
            writeln!(out, "#{prop_id}=IFCPROPERTYSINGLEVALUE('{name}',$,IFCLABEL('{value}'),$);").unwrap();
            prop_ids.push(prop_id);
        }

        let pset_id = id.next();
        let escaped_name = escape_ifc(pset_name);
        let refs: String = prop_ids.iter().map(|i| format!("#{i}")).collect::<Vec<_>>().join(",");
        let guid = format!("P{:021}", pset_id);
        writeln!(out, "#{pset_id}=IFCPROPERTYSET('{guid}',#{owner},'{escaped_name}',$,({refs}));").unwrap();

        let rel_id = id.next();
        let rel_guid = format!("R{:021}", rel_id);
        writeln!(out, "#{rel_id}=IFCRELDEFINESBYPROPERTIES('{rel_guid}',#{owner},$,$,(#{product_id}),#{pset_id});").unwrap();
    }
}

/// Write IFCELEMENTQUANTITY + IFCQUANTITY* + IFCRELDEFINESBYPROPERTIES.
fn write_quantities(
    out: &mut String,
    id: &mut IdCounter,
    quantities: &[crate::types::IfcQuantity],
    product_id: u32,
    owner: u32,
) {
    if quantities.is_empty() {
        return;
    }

    // Group by quantity set
    let mut groups: HashMap<String, Vec<&crate::types::IfcQuantity>> = HashMap::new();
    for q in quantities {
        let key = q.quantity_set.as_deref().unwrap_or("Quantities").to_string();
        groups.entry(key).or_default().push(q);
    }

    for (qset_name, quants) in &groups {
        let mut quant_ids = Vec::new();

        for q in quants {
            let q_id = id.next();
            let name = escape_ifc(&q.name);
            let ifc_type = match q.quantity_type.as_str() {
                "Length" => "IFCQUANTITYLENGTH",
                "Area" => "IFCQUANTITYAREA",
                "Volume" => "IFCQUANTITYVOLUME",
                "Count" => "IFCQUANTITYCOUNT",
                "Weight" => "IFCQUANTITYWEIGHT",
                _ => "IFCQUANTITYLENGTH",
            };
            writeln!(out, "#{q_id}={ifc_type}('{name}',$,$,{},\
$);", q.value).unwrap();
            quant_ids.push(q_id);
        }

        let qset_id = id.next();
        let escaped_name = escape_ifc(qset_name);
        let refs: String = quant_ids.iter().map(|i| format!("#{i}")).collect::<Vec<_>>().join(",");
        let guid = format!("Q{:021}", qset_id);
        writeln!(out, "#{qset_id}=IFCELEMENTQUANTITY('{guid}',#{owner},'{escaped_name}',$,$,({refs}));").unwrap();

        let rel_id = id.next();
        let rel_guid = format!("D{:021}", rel_id);
        writeln!(out, "#{rel_id}=IFCRELDEFINESBYPROPERTIES('{rel_guid}',#{owner},$,$,(#{product_id}),#{qset_id});").unwrap();
    }
}

/// Write IFCMATERIAL (+ optional layers) + IFCRELASSOCIATESMATERIAL.
/// Deduplicates materials by name across elements.
fn write_material(
    out: &mut String,
    id: &mut IdCounter,
    shared: &mut SharedEntities,
    mat: &crate::types::IfcMaterialInfo,
    product_id: u32,
    owner: u32,
) {
    let mat_entity_id = if let Some(&existing) = shared.materials.get(&mat.name) {
        existing
    } else {
        if mat.layers.is_empty() {
            // Simple material
            let mat_id = id.next();
            let name = escape_ifc(&mat.name);
            let category = mat.category.as_ref().map(|c| format!("'{}'", escape_ifc(c))).unwrap_or_else(|| "$".to_string());
            writeln!(out, "#{mat_id}=IFCMATERIAL('{name}',$,{category});").unwrap();
            shared.materials.insert(mat.name.clone(), mat_id);
            mat_id
        } else {
            // Material layer set
            let mut layer_ids = Vec::new();
            for layer in &mat.layers {
                let layer_mat_id = if let Some(&existing) = shared.materials.get(&layer.material_name) {
                    existing
                } else {
                    let mid = id.next();
                    let name = escape_ifc(&layer.material_name);
                    writeln!(out, "#{mid}=IFCMATERIAL('{name}',$,$);").unwrap();
                    shared.materials.insert(layer.material_name.clone(), mid);
                    mid
                };
                let lid = id.next();
                let thickness = layer.thickness.unwrap_or(0.0);
                writeln!(out, "#{lid}=IFCMATERIALLAYER(#{layer_mat_id},{thickness},$,$,$,$,$);").unwrap();
                layer_ids.push(lid);
            }
            let layer_set_id = id.next();
            let refs: String = layer_ids.iter().map(|i| format!("#{i}")).collect::<Vec<_>>().join(",");
            let name = escape_ifc(&mat.name);
            writeln!(out, "#{layer_set_id}=IFCMATERIALLAYERSET(({refs}),'{name}',$);").unwrap();
            shared.materials.insert(mat.name.clone(), layer_set_id);
            layer_set_id
        }
    };

    let rel_id = id.next();
    let rel_guid = format!("M{:021}", rel_id);
    writeln!(out, "#{rel_id}=IFCRELASSOCIATESMATERIAL('{rel_guid}',#{owner},$,$,(#{product_id}),#{mat_entity_id});").unwrap();
}

/// Write type product entity + IFCRELDEFINESBYTYPE.
/// Deduplicates type entities by name.
fn write_type(
    out: &mut String,
    id: &mut IdCounter,
    shared: &mut SharedEntities,
    type_info: &crate::types::IfcTypeInfo,
    product_id: u32,
    owner: u32,
) {
    let type_key = format!("{}:{}", type_info.ifc_type, type_info.name.as_deref().unwrap_or(""));
    let type_entity_id = if let Some(&existing) = shared.types.get(&type_key) {
        existing
    } else {
        let type_id = id.next();
        let ifc_type = map_to_type_product(&type_info.ifc_type);
        let name = ifc_str_or_null(&type_info.name);
        let guid = format!("T{:021}", type_id);

        let pred = type_info.predefined_type.as_deref()
            .map(|p| if p.starts_with('.') { p.to_string() } else { format!(".{p}.") })
            .unwrap_or_else(|| "$".to_string());

        // Type product: GlobalId, OwnerHistory, Name, Description, ApplicableOccurrence,
        //               HasPropertySets, RepresentationMaps, Tag, ElementType, PredefinedType
        writeln!(out, "#{type_id}={ifc_type}('{guid}',#{owner},{name},$,$,$,$,$,$,{pred});").unwrap();
        shared.types.insert(type_key, type_id);
        type_id
    };

    let rel_id = id.next();
    let rel_guid = format!("Y{:021}", rel_id);
    writeln!(out, "#{rel_id}=IFCRELDEFINESBYTYPE('{rel_guid}',#{owner},$,$,(#{product_id}),#{type_entity_id});").unwrap();
}

/// Write IFCCLASSIFICATION + IFCCLASSIFICATIONREFERENCE + IFCRELASSOCIATESCLASSIFICATION.
/// Deduplicates classification systems.
fn write_classification(
    out: &mut String,
    id: &mut IdCounter,
    shared: &mut SharedEntities,
    classification: &crate::types::IfcClassificationInfo,
    product_id: u32,
    owner: u32,
) {
    let class_system_id = if let Some(&existing) = shared.classifications.get(&classification.system_name) {
        existing
    } else {
        let class_id = id.next();
        let source = classification.system_source.as_ref()
            .map(|s| format!("'{}'", escape_ifc(s)))
            .unwrap_or_else(|| "$".to_string());
        let name = escape_ifc(&classification.system_name);
        writeln!(out, "#{class_id}=IFCCLASSIFICATION({source},$,$,'{name}',$,$,$);").unwrap();
        shared.classifications.insert(classification.system_name.clone(), class_id);
        class_id
    };

    let ref_id = id.next();
    let ref_name = escape_ifc(&classification.name);
    writeln!(out, "#{ref_id}=IFCCLASSIFICATIONREFERENCE($,'{ref_name}',$,#{class_system_id},$,$);").unwrap();

    let rel_id = id.next();
    let rel_guid = format!("C{:021}", rel_id);
    writeln!(out, "#{rel_id}=IFCRELASSOCIATESCLASSIFICATION('{rel_guid}',#{owner},$,$,(#{product_id}),#{ref_id});").unwrap();
}

// --- Helpers ---

/// Map our parsed IFC type to a valid IfcProduct subtype for export.
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

/// Map a type info ifc_type string to a valid IFC type product entity.
fn map_to_type_product(ifc_type: &str) -> &'static str {
    let upper = ifc_type.to_uppercase();
    let name = upper.strip_prefix("IFCTYPE").unwrap_or(&upper);
    match name {
        // Direct matches for IfcType enum debug format
        _ if upper.contains("SANITARYTERMINALTYPE") => "IFCSANITARYTERMINALTYPE",
        _ if upper.contains("WALLTYPE") => "IFCWALLTYPE",
        _ if upper.contains("DOORTYPE") => "IFCDOORTYPE",
        _ if upper.contains("WINDOWTYPE") => "IFCWINDOWTYPE",
        _ if upper.contains("SLABTYPE") => "IFCSLABTYPE",
        _ if upper.contains("COLUMNTYPE") => "IFCCOLUMNTYPE",
        _ if upper.contains("BEAMTYPE") => "IFCBEAMTYPE",
        _ if upper.contains("FURNISHINGELEMENTTYPE") => "IFCFURNISHINGELEMENTTYPE",
        _ if upper.contains("COVERINGTYPE") => "IFCCOVERINGTYPE",
        _ if upper.contains("FLOWTERMINALTYPE") => "IFCFLOWTERMINALTYPE",
        _ if upper.contains("FLOWSEGMENTTYPE") => "IFCFLOWSEGMENTTYPE",
        _ => "IFCBUILDINGELEMENTPROXYTYPE",
    }
}

/// Check if a product type needs a PredefinedType attribute.
fn needs_predefined_type(ifc_type: &str) -> bool {
    matches!(ifc_type,
        "IFCWALL" | "IFCDOOR" | "IFCWINDOW" | "IFCSLAB" | "IFCCOLUMN" | "IFCBEAM" |
        "IFCSTAIR" | "IFCRAILING" | "IFCPLATE" | "IFCMEMBER" | "IFCCOVERING" |
        "IFCSANITARYTERMINAL" | "IFCFLOWSEGMENT" | "IFCFLOWTERMINAL" |
        "IFCFURNISHINGELEMENT" | "IFCSPACE" | "IFCBUILDINGELEMENTPROXY"
    )
}

/// Escape a string for IFC STEP format (single quotes doubled).
fn escape_ifc(s: &str) -> String {
    s.replace('\'', "''")
}

/// Format an optional string as an IFC attribute: 'value' or $.
fn ifc_str_or_null(s: &Option<String>) -> String {
    match s {
        Some(v) if !v.is_empty() => format!("'{}'", escape_ifc(v)),
        _ => "$".to_string(),
    }
}

/// Track shared entities to avoid duplicating materials, types, classifications.
struct SharedEntities {
    materials: HashMap<String, u32>,
    types: HashMap<String, u32>,
    classifications: HashMap<String, u32>,
}

impl SharedEntities {
    fn new() -> Self {
        Self {
            materials: HashMap::new(),
            types: HashMap::new(),
            classifications: HashMap::new(),
        }
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
