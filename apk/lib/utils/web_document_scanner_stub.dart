/// Web stub for cunning_document_scanner.
///
/// Document scanning requires the device camera in a native context and is
/// not available in the browser.  Calls silently return empty results on web.
library web_document_scanner_stub;

class CunningDocumentScanner {
  /// Always returns an empty list on web.
  static Future<List<String>?> getPictures({
    int noOfPages = 1,
    bool isGalleryImportAllowed = false,
  }) async => null;
}
