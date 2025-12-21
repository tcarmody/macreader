"""
Text Extraction - Extract text from various file formats.

Supports:
- PDF (via PyMuPDF/fitz)
- DOCX (via python-docx)
- HTML (via BeautifulSoup)
- TXT/MD (plain text)
"""

import re
from pathlib import Path

from bs4 import BeautifulSoup


class ExtractionError(Exception):
    """Error during text extraction."""
    pass


def extract_pdf_text(file_path: Path) -> str:
    """
    Extract text from a PDF file.

    Args:
        file_path: Path to the PDF file

    Returns:
        Extracted text content

    Raises:
        ExtractionError: If extraction fails
    """
    try:
        import fitz  # PyMuPDF
    except ImportError:
        raise ExtractionError("PyMuPDF (fitz) not installed. Run: pip install pymupdf")

    try:
        doc = fitz.open(str(file_path))
        text_parts = []

        for page in doc:
            text = page.get_text()
            if text.strip():
                text_parts.append(text)

        doc.close()

        content = "\n\n".join(text_parts)
        # Clean up excessive whitespace
        content = re.sub(r"\n{3,}", "\n\n", content)
        return content.strip()

    except Exception as e:
        raise ExtractionError(f"Failed to extract PDF text: {e}")


def extract_docx_text(file_path: Path) -> str:
    """
    Extract text from a DOCX file.

    Args:
        file_path: Path to the DOCX file

    Returns:
        Extracted text content

    Raises:
        ExtractionError: If extraction fails
    """
    try:
        from docx import Document
    except ImportError:
        raise ExtractionError("python-docx not installed. Run: pip install python-docx")

    try:
        doc = Document(str(file_path))
        paragraphs = []

        for para in doc.paragraphs:
            text = para.text.strip()
            if text:
                paragraphs.append(text)

        return "\n\n".join(paragraphs)

    except Exception as e:
        raise ExtractionError(f"Failed to extract DOCX text: {e}")


def extract_html_text(content: str) -> str:
    """
    Extract text from HTML content.

    Args:
        content: HTML string

    Returns:
        Extracted text content
    """
    soup = BeautifulSoup(content, "html.parser")

    # Remove script and style elements
    for tag in soup.find_all(["script", "style", "nav", "header", "footer"]):
        tag.decompose()

    # Get text with some structure preserved
    text = soup.get_text(separator="\n")

    # Clean up whitespace
    lines = [line.strip() for line in text.splitlines()]
    lines = [line for line in lines if line]
    return "\n\n".join(lines)


def extract_text_file(file_path: Path) -> str:
    """
    Read a plain text or markdown file.

    Args:
        file_path: Path to the text file

    Returns:
        File content

    Raises:
        ExtractionError: If reading fails
    """
    try:
        return file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        try:
            return file_path.read_text(encoding="latin-1")
        except Exception as e:
            raise ExtractionError(f"Failed to read text file: {e}")
    except Exception as e:
        raise ExtractionError(f"Failed to read text file: {e}")


def extract_text(file_path: Path, content_type: str) -> str:
    """
    Extract text from a file based on content type.

    Args:
        file_path: Path to the file
        content_type: Type of content (pdf, docx, html, txt, md)

    Returns:
        Extracted text content

    Raises:
        ExtractionError: If extraction fails or type is unsupported
    """
    content_type = content_type.lower()

    if content_type == "pdf":
        return extract_pdf_text(file_path)
    elif content_type == "docx":
        return extract_docx_text(file_path)
    elif content_type == "html":
        html_content = file_path.read_text(encoding="utf-8")
        return extract_html_text(html_content)
    elif content_type in ("txt", "md", "markdown", "text"):
        return extract_text_file(file_path)
    else:
        raise ExtractionError(f"Unsupported content type: {content_type}")


def detect_content_type(filename: str) -> str:
    """
    Detect content type from filename extension.

    Args:
        filename: Name of the file

    Returns:
        Content type string (pdf, docx, html, txt, md)

    Raises:
        ExtractionError: If extension is not supported
    """
    ext = Path(filename).suffix.lower()

    mapping = {
        ".pdf": "pdf",
        ".docx": "docx",
        ".doc": "docx",  # Try docx parser for .doc
        ".html": "html",
        ".htm": "html",
        ".txt": "txt",
        ".md": "md",
        ".markdown": "md",
        ".text": "txt",
    }

    if ext in mapping:
        return mapping[ext]

    raise ExtractionError(f"Unsupported file extension: {ext}")
