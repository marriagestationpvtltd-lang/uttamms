/// Generic API Response Wrapper
///
/// Provides a consistent way to handle API responses across the app.
/// Supports both success and error states with proper typing.

class ApiResponse<T> {
  final T? data;
  final String? error;
  final bool isSuccess;
  final int? statusCode;

  const ApiResponse._({
    this.data,
    this.error,
    required this.isSuccess,
    this.statusCode,
  });

  /// Create a successful response.
  factory ApiResponse.success(T data, {int? statusCode}) {
    return ApiResponse._(
      data: data,
      isSuccess: true,
      statusCode: statusCode ?? 200,
    );
  }

  /// Create an error response.
  factory ApiResponse.error(String error, {int? statusCode}) {
    return ApiResponse._(
      error: error,
      isSuccess: false,
      statusCode: statusCode,
    );
  }

  /// Returns [data] or throws an [Exception] if the response is not successful.
  T get dataOrThrow {
    if (isSuccess && data != null) return data!;
    throw Exception(error ?? 'Unknown error');
  }

  /// Returns [data] if successful, otherwise [defaultValue].
  T dataOr(T defaultValue) => isSuccess && data != null ? data! : defaultValue;

  @override
  String toString() {
    return isSuccess
        ? 'ApiResponse.success(data: $data, statusCode: $statusCode)'
        : 'ApiResponse.error(error: $error, statusCode: $statusCode)';
  }
}
