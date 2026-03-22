use ifc_lite_core::EntityDecoder;
use rustc_hash::FxHashMap;

use crate::parser::ParsedIfc;

/// Default RGBA colors by IFC type (muted architectural palette).
pub fn default_color_for_type(ifc_type: &str) -> [f32; 4] {
    match ifc_type {
        "IFCWALL" | "IFCWALLSTANDARDCASE" => [0.85, 0.83, 0.80, 1.0],
        "IFCSLAB" => [0.70, 0.70, 0.70, 1.0],
        "IFCBEAM" | "IFCCOLUMN" | "IFCMEMBER" => [0.75, 0.73, 0.68, 1.0],
        "IFCWINDOW" => [0.6, 0.78, 0.9, 0.4],
        "IFCDOOR" => [0.55, 0.35, 0.20, 1.0],
        "IFCROOF" => [0.6, 0.25, 0.22, 1.0],
        "IFCSTAIR" | "IFCSTAIRFLIGHT" => [0.78, 0.76, 0.72, 1.0],
        "IFCRAILING" => [0.45, 0.45, 0.50, 1.0],
        "IFCPLATE" => [0.80, 0.80, 0.82, 1.0],
        "IFCFOOTING" | "IFCPILE" => [0.65, 0.65, 0.60, 1.0],
        "IFCFURNISHINGELEMENT" => [0.6, 0.5, 0.4, 1.0],
        "IFCSPACE" => [0.5, 0.7, 0.5, 0.15],
        "IFCCOVERING" => [0.9, 0.9, 0.88, 1.0],
        _ => [0.8, 0.8, 0.8, 1.0],
    }
}

/// Build a mapping from geometry representation IDs to RGBA colors.
///
/// Walks IfcStyledItem → IfcSurfaceStyle → IfcSurfaceStyleRendering → IfcColourRgb.
pub fn build_style_index(
    parsed: &ParsedIfc,
    decoder: &mut EntityDecoder,
) -> FxHashMap<u32, [f32; 4]> {
    let mut style_map: FxHashMap<u32, [f32; 4]> = FxHashMap::default();

    for entity in &parsed.all_entities {
        if entity.ifc_type != "IFCSTYLEDITEM" {
            continue;
        }

        let Ok(decoded) = decoder.decode_by_id(entity.id) else {
            continue;
        };

        // IfcStyledItem(Item, Styles, Name)
        let Some(item_id) = decoded.get_ref(0) else {
            continue;
        };

        if let Some(color) = extract_color_from_styled_item(decoder, &decoded) {
            style_map.insert(item_id, color);
        }
    }

    style_map
}

/// Follow the style chain from an IfcStyledItem to extract RGBA color.
fn extract_color_from_styled_item(
    decoder: &mut EntityDecoder,
    styled_item: &ifc_lite_core::DecodedEntity,
) -> Option<[f32; 4]> {
    // IfcStyledItem.Styles (attribute index 1) — list of style refs
    let styles_attr = styled_item.get(1)?;
    let style_entities = decoder.resolve_ref_list(styles_attr).ok()?;

    for style in &style_entities {
        let type_str = format!("{}", style.ifc_type);

        // Direct IfcSurfaceStyle
        if type_str.contains("SurfaceStyle") && !type_str.contains("Rendering") {
            if let Some(color) = extract_color_from_surface_style(decoder, style) {
                return Some(color);
            }
        }

        // IfcPresentationStyleAssignment.Styles (attribute 0)
        if let Some(inner_attr) = style.get(0) {
            if let Ok(inner_styles) = decoder.resolve_ref_list(inner_attr) {
                for inner in &inner_styles {
                    if let Some(color) = extract_color_from_surface_style(decoder, inner) {
                        return Some(color);
                    }
                }
            }
        }
    }

    None
}

/// Extract color from an IfcSurfaceStyle entity.
fn extract_color_from_surface_style(
    decoder: &mut EntityDecoder,
    surface_style: &ifc_lite_core::DecodedEntity,
) -> Option<[f32; 4]> {
    // IfcSurfaceStyle(Name, Side, Styles)
    // Styles (attribute 2) may contain IfcSurfaceStyleRendering
    let styles_attr = surface_style.get(2)?;
    let renderings = decoder.resolve_ref_list(styles_attr).ok()?;

    for rendering in &renderings {
        // IfcSurfaceStyleRendering.SurfaceColour (attribute 0) → IfcColourRgb ref
        let color_attr = rendering.get(0)?;
        let color_entity = decoder.resolve_ref(color_attr).ok()??;

        // IfcColourRgb(Name, Red, Green, Blue)
        let r = color_entity.get_float(1)?;
        let g = color_entity.get_float(2)?;
        let b = color_entity.get_float(3)?;

        // Transparency (attribute 1 of rendering)
        let alpha = rendering
            .get_float(1)
            .map(|t| 1.0 - t) // IFC: 0=opaque, 1=transparent
            .unwrap_or(1.0);

        return Some([r as f32, g as f32, b as f32, alpha as f32]);
    }

    None
}
