use gltf_json as json;
use json::validation::Checked::Valid;

use crate::error::IfcArError;
use crate::types::{ElementColor, InternalElement, ModelBounds};

/// Export a list of IFC elements to a GLB binary.
///
/// Each element with geometry becomes a glTF mesh with a PBR material.
/// The scene root contains all meshes as child nodes.
pub fn export_glb(elements: &[InternalElement], _bounds: &ModelBounds) -> Result<Vec<u8>, IfcArError> {
    let elements_with_geometry: Vec<&InternalElement> = elements
        .iter()
        .filter(|e| e.geometry.is_some())
        .collect();

    if elements_with_geometry.is_empty() {
        return Err(IfcArError::gltf("No elements with geometry to export"));
    }

    let mut root = json::Root::default();
    let mut bin_data: Vec<u8> = Vec::new();
    let mut buffer_views = Vec::new();
    let mut accessors = Vec::new();
    let mut meshes = Vec::new();
    let mut materials = Vec::new();
    let mut nodes = Vec::new();
    let mut child_indices = Vec::new();

    for element in &elements_with_geometry {
        let mesh = element.geometry.as_ref().unwrap();
        let material_index = materials.len() as u32;
        let mesh_index = meshes.len() as u32;
        let node_index = nodes.len() as u32;

        // --- Material ---
        materials.push(create_material(&element.color, &element.ifc_type));

        // --- Positions buffer view ---
        let pos_bytes = to_bytes_f32(&mesh.positions);
        let pos_view_idx = buffer_views.len() as u32;
        let pos_byte_offset = bin_data.len();
        bin_data.extend_from_slice(&pos_bytes);
        pad_to_4_bytes(&mut bin_data);
        buffer_views.push(json::buffer::View {
            buffer: json::Index::new(0),
            byte_length: json::validation::USize64(pos_bytes.len() as u64),
            byte_offset: Some(json::validation::USize64(pos_byte_offset as u64)),
            byte_stride: None,
            extensions: Default::default(),
            extras: Default::default(),
            name: None,
            target: Some(Valid(json::buffer::Target::ArrayBuffer)),
        });

        // Positions accessor
        let pos_acc_idx = accessors.len() as u32;
        let (pos_min, pos_max) = compute_min_max_vec3(&mesh.positions);
        accessors.push(json::Accessor {
            buffer_view: Some(json::Index::new(pos_view_idx)),
            byte_offset: Some(json::validation::USize64(0)),
            count: json::validation::USize64((mesh.positions.len() / 3) as u64),
            component_type: Valid(json::accessor::GenericComponentType(
                json::accessor::ComponentType::F32,
            )),
            extensions: Default::default(),
            extras: Default::default(),
            type_: Valid(json::accessor::Type::Vec3),
            min: Some(json::Value::from(pos_min.to_vec())),
            max: Some(json::Value::from(pos_max.to_vec())),
            name: None,
            normalized: false,
            sparse: None,
        });

        // --- Normals buffer view ---
        let norm_bytes = to_bytes_f32(&mesh.normals);
        let norm_view_idx = buffer_views.len() as u32;
        let norm_byte_offset = bin_data.len();
        bin_data.extend_from_slice(&norm_bytes);
        pad_to_4_bytes(&mut bin_data);
        buffer_views.push(json::buffer::View {
            buffer: json::Index::new(0),
            byte_length: json::validation::USize64(norm_bytes.len() as u64),
            byte_offset: Some(json::validation::USize64(norm_byte_offset as u64)),
            byte_stride: None,
            extensions: Default::default(),
            extras: Default::default(),
            name: None,
            target: Some(Valid(json::buffer::Target::ArrayBuffer)),
        });

        // Normals accessor
        let norm_acc_idx = accessors.len() as u32;
        accessors.push(json::Accessor {
            buffer_view: Some(json::Index::new(norm_view_idx)),
            byte_offset: Some(json::validation::USize64(0)),
            count: json::validation::USize64((mesh.normals.len() / 3) as u64),
            component_type: Valid(json::accessor::GenericComponentType(
                json::accessor::ComponentType::F32,
            )),
            extensions: Default::default(),
            extras: Default::default(),
            type_: Valid(json::accessor::Type::Vec3),
            min: None,
            max: None,
            name: None,
            normalized: false,
            sparse: None,
        });

        // --- Indices buffer view ---
        let idx_bytes = to_bytes_u32(&mesh.indices);
        let idx_view_idx = buffer_views.len() as u32;
        let idx_byte_offset = bin_data.len();
        bin_data.extend_from_slice(&idx_bytes);
        pad_to_4_bytes(&mut bin_data);
        buffer_views.push(json::buffer::View {
            buffer: json::Index::new(0),
            byte_length: json::validation::USize64(idx_bytes.len() as u64),
            byte_offset: Some(json::validation::USize64(idx_byte_offset as u64)),
            byte_stride: None,
            extensions: Default::default(),
            extras: Default::default(),
            name: None,
            target: Some(Valid(json::buffer::Target::ElementArrayBuffer)),
        });

        // Indices accessor
        let idx_acc_idx = accessors.len() as u32;
        accessors.push(json::Accessor {
            buffer_view: Some(json::Index::new(idx_view_idx)),
            byte_offset: Some(json::validation::USize64(0)),
            count: json::validation::USize64(mesh.indices.len() as u64),
            component_type: Valid(json::accessor::GenericComponentType(
                json::accessor::ComponentType::U32,
            )),
            extensions: Default::default(),
            extras: Default::default(),
            type_: Valid(json::accessor::Type::Scalar),
            min: None,
            max: None,
            name: None,
            normalized: false,
            sparse: None,
        });

        // --- Mesh primitive ---
        let primitive = json::mesh::Primitive {
            attributes: {
                let mut map = std::collections::BTreeMap::new();
                map.insert(
                    Valid(json::mesh::Semantic::Positions),
                    json::Index::new(pos_acc_idx),
                );
                map.insert(
                    Valid(json::mesh::Semantic::Normals),
                    json::Index::new(norm_acc_idx),
                );
                map
            },
            extensions: Default::default(),
            extras: Default::default(),
            indices: Some(json::Index::new(idx_acc_idx)),
            material: Some(json::Index::new(material_index)),
            mode: Valid(json::mesh::Mode::Triangles),
            targets: None,
        };

        meshes.push(json::Mesh {
            extensions: Default::default(),
            extras: Default::default(),
            name: element.name.clone(),
            primitives: vec![primitive],
            weights: None,
        });

        // --- Node ---
        nodes.push(json::Node {
            camera: None,
            children: None,
            extensions: Default::default(),
            extras: Default::default(),
            matrix: None,
            mesh: Some(json::Index::new(mesh_index)),
            name: element.name.clone(),
            rotation: None,
            scale: None,
            translation: None,
            skin: None,
            weights: None,
        });

        child_indices.push(json::Index::new(node_index));
    }

    // Scene root node
    let root_node_idx = nodes.len() as u32;
    nodes.push(json::Node {
        camera: None,
        children: Some(child_indices),
        extensions: Default::default(),
        extras: Default::default(),
        matrix: None,
        mesh: None,
        name: Some("IFC Model".to_string()),
        rotation: None,
        scale: None,
        translation: None,
        skin: None,
        weights: None,
    });

    // Buffer
    root.buffers = vec![json::Buffer {
        byte_length: json::validation::USize64(bin_data.len() as u64),
        extensions: Default::default(),
        extras: Default::default(),
        name: None,
        uri: None,
    }];

    root.buffer_views = buffer_views;
    root.accessors = accessors;
    root.meshes = meshes;
    root.materials = materials;
    root.nodes = nodes;
    root.scenes = vec![json::Scene {
        extensions: Default::default(),
        extras: Default::default(),
        name: Some("IFC Scene".to_string()),
        nodes: vec![json::Index::new(root_node_idx)],
    }];
    root.scene = Some(json::Index::new(0));

    // Serialize to GLB
    let json_string = json::serialize::to_string(&root)
        .map_err(|e| IfcArError::gltf(format!("JSON serialization failed: {e}")))?;

    let json_bytes = json_string.as_bytes();
    let glb = assemble_glb(json_bytes, &bin_data);

    Ok(glb)
}

/// Create a PBR material from an element color.
fn create_material(color: &ElementColor, ifc_type: &str) -> json::Material {
    let alpha_mode = if color.a < 1.0 {
        Valid(json::material::AlphaMode::Blend)
    } else {
        Valid(json::material::AlphaMode::Opaque)
    };

    json::Material {
        alpha_cutoff: None,
        alpha_mode,
        double_sided: true,
        extensions: Default::default(),
        extras: Default::default(),
        name: Some(ifc_type.to_string()),
        pbr_metallic_roughness: json::material::PbrMetallicRoughness {
            base_color_factor: json::material::PbrBaseColorFactor([
                color.r, color.g, color.b, color.a,
            ]),
            base_color_texture: None,
            metallic_factor: json::material::StrengthFactor(0.0),
            roughness_factor: json::material::StrengthFactor(0.8),
            metallic_roughness_texture: None,
            extensions: Default::default(),
            extras: Default::default(),
        },
        normal_texture: None,
        occlusion_texture: None,
        emissive_texture: None,
        emissive_factor: json::material::EmissiveFactor([0.0, 0.0, 0.0]),
    }
}

/// Assemble a GLB binary from JSON and BIN chunks.
fn assemble_glb(json_bytes: &[u8], bin_data: &[u8]) -> Vec<u8> {
    // Pad JSON to 4-byte alignment with spaces
    let json_padding = (4 - (json_bytes.len() % 4)) % 4;
    let json_chunk_length = json_bytes.len() + json_padding;

    // Pad BIN to 4-byte alignment with zeros
    let bin_padding = (4 - (bin_data.len() % 4)) % 4;
    let bin_chunk_length = bin_data.len() + bin_padding;

    // GLB header (12 bytes) + JSON chunk (8 + data) + BIN chunk (8 + data)
    let total_length = 12 + 8 + json_chunk_length + 8 + bin_chunk_length;

    let mut glb = Vec::with_capacity(total_length);

    // GLB header
    glb.extend_from_slice(b"glTF");                         // magic
    glb.extend_from_slice(&2u32.to_le_bytes());              // version
    glb.extend_from_slice(&(total_length as u32).to_le_bytes()); // total length

    // JSON chunk
    glb.extend_from_slice(&(json_chunk_length as u32).to_le_bytes()); // chunk length
    glb.extend_from_slice(&0x4E4F534Au32.to_le_bytes());              // chunk type "JSON"
    glb.extend_from_slice(json_bytes);
    glb.extend_from_slice(&vec![0x20u8; json_padding]);               // pad with spaces

    // BIN chunk
    glb.extend_from_slice(&(bin_chunk_length as u32).to_le_bytes()); // chunk length
    glb.extend_from_slice(&0x004E4942u32.to_le_bytes());             // chunk type "BIN\0"
    glb.extend_from_slice(bin_data);
    glb.extend_from_slice(&vec![0u8; bin_padding]);                  // pad with zeros

    glb
}

/// Convert f32 slice to raw bytes.
fn to_bytes_f32(data: &[f32]) -> Vec<u8> {
    data.iter().flat_map(|f| f.to_le_bytes()).collect()
}

/// Convert u32 slice to raw bytes.
fn to_bytes_u32(data: &[u32]) -> Vec<u8> {
    data.iter().flat_map(|i| i.to_le_bytes()).collect()
}

/// Pad buffer to 4-byte alignment.
fn pad_to_4_bytes(data: &mut Vec<u8>) {
    let padding = (4 - (data.len() % 4)) % 4;
    data.extend(std::iter::repeat(0u8).take(padding));
}

/// Compute min/max for VEC3 positions.
fn compute_min_max_vec3(positions: &[f32]) -> ([f32; 3], [f32; 3]) {
    let mut min = [f32::MAX; 3];
    let mut max = [f32::MIN; 3];

    for chunk in positions.chunks_exact(3) {
        for i in 0..3 {
            min[i] = min[i].min(chunk[i]);
            max[i] = max[i].max(chunk[i]);
        }
    }

    (min, max)
}
