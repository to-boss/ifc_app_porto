/// Error type compatible with UniFFI's flat enum errors.
/// The UDL declares this as a flat error enum, so variants carry no data.
/// Use the Display impl to get the details.
#[derive(Debug)]
pub enum IfcArError {
    ParseError,
    GeometryError,
    GltfExportError,
    InvalidInput,
}

impl std::fmt::Display for IfcArError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::ParseError => write!(f, "Failed to parse IFC file"),
            Self::GeometryError => write!(f, "Geometry processing failed"),
            Self::GltfExportError => write!(f, "GLB export failed"),
            Self::InvalidInput => write!(f, "Invalid input"),
        }
    }
}

impl std::error::Error for IfcArError {}

impl IfcArError {
    pub fn parse(_reason: impl Into<String>) -> Self {
        Self::ParseError
    }

    pub fn geometry(_reason: impl Into<String>) -> Self {
        Self::GeometryError
    }

    pub fn gltf(_reason: impl Into<String>) -> Self {
        Self::GltfExportError
    }

    pub fn invalid_input(_reason: impl Into<String>) -> Self {
        Self::InvalidInput
    }
}
