use std::fmt;

#[derive(Debug)]
#[allow(dead_code)]
pub enum CompressError {
    IoError(std::io::Error),
    DecodeError(String),
    EncodeError(String),
    UnsupportedFormat(String),
    InvalidParameter(String),
}

impl fmt::Display for CompressError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::IoError(e) => write!(f, "IO error: {e}"),
            Self::DecodeError(msg) => write!(f, "Decode error: {msg}"),
            Self::EncodeError(msg) => write!(f, "Encode error: {msg}"),
            Self::UnsupportedFormat(fmt_name) => write!(f, "Unsupported format: {fmt_name}"),
            Self::InvalidParameter(msg) => write!(f, "Invalid parameter: {msg}"),
        }
    }
}

impl From<std::io::Error> for CompressError {
    fn from(e: std::io::Error) -> Self {
        Self::IoError(e)
    }
}

impl From<image::ImageError> for CompressError {
    fn from(e: image::ImageError) -> Self {
        Self::DecodeError(e.to_string())
    }
}
