use std::fs;

#[test]
fn export_preserves_all_metadata() {
    let data = fs::read("../../test-fixtures/Objekt_WC.ifc").expect("read fixture");

    let result = ifc_ar_core::export_combined_ifc(data.clone(), vec![]).expect("export");

    // Properties
    assert!(result.contains("IFCPROPERTYSET"), "missing IFCPROPERTYSET");
    assert!(result.contains("IFCPROPERTYSINGLEVALUE"), "missing IFCPROPERTYSINGLEVALUE");

    // Quantities
    assert!(result.contains("IFCELEMENTQUANTITY"), "missing IFCELEMENTQUANTITY");
    assert!(result.contains("IFCQUANTITYLENGTH"), "missing IFCQUANTITYLENGTH");

    // Relationships
    assert!(result.contains("IFCRELDEFINESBYPROPERTIES"), "missing IFCRELDEFINESBYPROPERTIES");

    // Type
    assert!(result.contains("IFCRELDEFINESBYTYPE"), "missing IFCRELDEFINESBYTYPE");
    assert!(result.contains("IFCSANITARYTERMINALTYPE"), "missing IFCSANITARYTERMINALTYPE");

    // Classification
    assert!(result.contains("IFCCLASSIFICATIONREFERENCE"), "missing IFCCLASSIFICATIONREFERENCE");
    assert!(result.contains("IFCCLASSIFICATION("), "missing IFCCLASSIFICATION");
    assert!(result.contains("IFCRELASSOCIATESCLASSIFICATION"), "missing IFCRELASSOCIATESCLASSIFICATION");

    // PredefinedType preserved
    assert!(result.contains(".TOILETPAN."), "missing PredefinedType .TOILETPAN.");

    // Product has name (not all $)
    let has_named_product = result.lines().any(|l| {
        l.contains("IFCSANITARYTERMINAL(") && l.contains("'SN'")
    });
    assert!(has_named_product, "IFCSANITARYTERMINAL should have name 'SN'");
}

#[test]
fn export_room_preserves_materials() {
    let room = fs::read("../../test-fixtures/BaseRoom-v2.ifc").expect("read room");
    let result = ifc_ar_core::export_combined_ifc(room, vec![]).expect("export");

    assert!(result.contains("IFCMATERIAL("), "missing IFCMATERIAL");
    assert!(result.contains("IFCRELASSOCIATESMATERIAL("), "missing IFCRELASSOCIATESMATERIAL");
}

#[test]
fn export_combined_preserves_fixture_metadata() {
    let room = fs::read("../../test-fixtures/BaseRoom-v2.ifc").expect("read room");
    let fixture = fs::read("../../test-fixtures/Objekt_WC.ifc").expect("read fixture");

    let fixtures = vec![ifc_ar_core::FixtureExportInput {
        ifc_data: fixture,
        rel_x: 1.0,
        rel_y: 0.0,
        rel_z: -2.0,
        rotation_y: 0.0,
    }];

    let result = ifc_ar_core::export_combined_ifc(room, fixtures).expect("export");

    // Both room and fixture metadata should be present
    assert!(result.contains("IFCPROPERTYSET"), "missing properties from fixture");
    assert!(result.contains("IFCSANITARYTERMINALTYPE"), "missing type from fixture");
    assert!(result.contains("IFCWALL(") || result.contains("IFCSLAB("), "missing room elements");
}
