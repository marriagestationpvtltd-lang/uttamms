# Document Scanner Feature

## Overview
यो feature ले users लाई documents (जस्तै ID cards, passports, licenses) scan गर्न र upload गर्न मद्दत गर्छ। यसले automatic edge detection र cropping प्रदान गर्छ जसले document scanning लाई सजिलो र accurate बनाउँछ।

This feature helps users scan and upload documents (such as ID cards, passports, licenses) with automatic edge detection and cropping, making document scanning easier and more accurate.

## Key Features

### 1. Automatic Edge Detection
- Documents को edges automatically detect हुन्छ
- User ले corner points adjust गर्न सक्छ
- Detected edges highlight भएर देखिन्छ

### 2. Three Upload Options
Users ले तीन तरिकाले documents upload गर्न सक्छन्:

#### a) **Scan Document (Recommended)**
- Document scanner opens गर्छ
- Camera वा Gallery बाट image select गर्न सकिन्छ
- Automatic edge detection र cropping
- User ले crop area adjust गर्न सक्छ
- Best quality को लागि recommended

#### b) **Camera**
- Direct camera use गरेर photo खिच्न सकिन्छ
- Traditional image capture
- No automatic cropping

#### c) **Gallery**
- Existing photos बाट select गर्न सकिन्छ
- No automatic cropping

### 3. OCR Integration
- Document scan गरेपछि automatically OCR run हुन्छ
- Document ID/Number निकालिन्छ
- Nepali र English दुवै numerals support गर्छ
- User ले extracted text verify र edit गर्न सक्छ

## Technical Implementation

### Package Used
```yaml
cunning_document_scanner: ^1.3.3
```

### Service Files
1. **DocumentScannerService** (`lib/service/document_scanner_service.dart`)
   - Document scanning wrapper service
   - Methods for camera, gallery, and combined scanning
   - File path conversion utilities

2. **OCRService** (`lib/service/ocr_service.dart`)
   - Text extraction from documents
   - Nepali numeral support (०-९)
   - Pattern matching for document IDs

### Integration Points
- **ID Verification Screen** (`lib/Auth/Screen/signupscreen10.dart`)
  - Main integration point
  - Three upload options modal
  - Scanned image preview
  - Auto-OCR after scanning

## User Flow

### Document Scanning Flow
1. User navigates to ID verification screen
2. Selects document type (Passport, License, etc.)
3. Taps "Upload Document Photo"
4. Sees three options: Scan Document, Camera, Gallery
5. **If "Scan Document" selected:**
   - Document scanner opens
   - User can choose camera or gallery
   - Document edges are automatically detected
   - User can adjust corner points for perfect crop
   - User confirms the crop
   - Image is cropped and returned
6. OCR automatically runs on the cropped image
7. Document ID is extracted and shown in a dialog
8. User verifies and accepts the extracted ID
9. Document is ready for upload

### Benefits for Users
- ✅ क्लियर र professional looking documents
- ✅ Unnecessary background remove हुन्छ
- ✅ Document ID automatically extract हुन्छ
- ✅ Manual typing को जरुरत कम हुन्छ
- ✅ Upload quality राम्रो हुन्छ

## Code Examples

### Using Document Scanner
```dart
final DocumentScannerService _documentScanner = DocumentScannerService();

// Scan a document
Future<void> _scanDocument() async {
  final scannedPaths = await _documentScanner.scanDocument(
    numberOfPages: 1,
    allowGallery: true,
  );

  if (scannedPaths != null && scannedPaths.isNotEmpty) {
    setState(() {
      _scannedImagePath = scannedPaths.first;
    });
  }
}
```

### Displaying Scanned Image
```dart
if (_scannedImagePath != null)
  Image.file(
    File(_scannedImagePath!),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.cover,
  )
```

### Uploading Scanned Document
```dart
// Use scanned image if available, otherwise use selected image
final String imagePath = _scannedImagePath ?? _selectedImage!.path;
final imageFile = await http.MultipartFile.fromPath('photo', imagePath);
request.files.add(imageFile);
```

## Future Enhancements
- [ ] Multiple page document scanning
- [ ] PDF generation from scanned documents
- [ ] Brightness and contrast adjustment
- [ ] Color vs Black & White selection
- [ ] Document quality validation
- [ ] Cloud storage integration

## Support
For issues or questions, please contact the development team.
