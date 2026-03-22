fn main() {
    let data = std::fs::read("test-fixtures/Objekt_WC.ifc").expect("read file");
    println!("File size: {} bytes", data.len());

    match ifc_ar_core::parse_ifc(data) {
        Ok(model) => {
            println!("Parse OK: {} elements", model.elements.len());
            for e in &model.elements {
                let geo = if let Some(ref g) = e.geometry {
                    format!("{} verts, {} tris", g.positions.len() / 3, g.indices.len() / 3)
                } else {
                    "no geometry".to_string()
                };
                println!("  #{} {} ({}) — {}", e.id, e.ifc_type, e.name.as_deref().unwrap_or("?"), geo);
            }
        }
        Err(e) => println!("Parse FAILED: {:?}", e),
    }
}
