/// Generic API Response Wrapper
///
/// Provides a consistent way to handle API responses across the app.
/// Supports both success and error states with proper typing.
///
/// Usage:
/// ```dart
/// final response = await service.fetchData();
/// if (response.isSuccess) {
///   // Use response.data
/// } else {
///   // Handle response.error
/// }
/// ```

class ApiResponse<T> {
  final T? data;
  final String? error;
  final bool isSuccess;
  final int? statusCode;
  final Map<String, dynamic>? metadata;

  ApiResponse._({
    this.data,
    this.error,
    required this.isSuccess,
    this.statusCode,
    this.metadata,
  });

  /// Create a successful response
  factory ApiResponse.success(
    T data, {
    int? statusCode,
    Map<String, dynamic>? metadata,
  }) {
    return ApiResponse._(
      data: data,
      error: null,
      isSuccess: true,
      statusCode: statusCode ?? 200,
      metadata: metadata,
    );
  }

  /// Create an error response
  factory ApiResponse.error(
    String error, {
    int? statusCode,
    Map<String, dynamic>? metadata,
  }) {
    return ApiResponse._(
      data: null,
      error: error,
      isSuccess: false,
      statusCode: statusCode,
      metadata: metadata,
    );
  }

  /// Create a loading state response
  factory ApiResponse.loading() {
    return ApiResponse._(
      data: null,
      error: null,
      isSuccess: false,
      statusCode: null,
      metadata: {'loading': true},
    );
  }

  /// Check if response is loading
  bool get isLoading => metadata?['loading'] == true;

  /// Get data or throw error
  T get dataOrThrow {
    if (isSuccess && data != null) {
      return data!;
    } else {
      throw Exception(error ?? 'Unknown error');
    }
  }

  /// Get data or return default value
  T dataOr(T defaultValue) {
    return isSuccess && data != null ? data! : defaultValue;
  }

  /// Transform data
  ApiResponse<R> map<R>(R Function(T data) transform) {
    if (isSuccess && data != null) {
      try {
        return ApiResponse.success(
          transform(data!),
          statusCode: statusCode,
          metadata: metadata,
        );
      } catch (e) {
        return ApiResponse.error(
          'Transform error: ${e.toString()}',
          statusCode: statusCode,
          metadata: metadata,
        );
      }
    } else {
      return ApiResponse.error(
        error ?? 'No data to transform',
        statusCode: statusCode,
        metadata: metadata,
      );
    }
  }

  /// Execute callback based on state
  R when<R>({
    required R Function(T data) success,
    required R Function(String error) error,
    R Function()? loading,
  }) {
    if (isLoading && loading != null) {
      return loading();
    } else if (isSuccess && data != null) {
      return success(data!);
    } else {
      return error(this.error ?? 'Unknown error');
    }
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'ApiResponse.success(data: $data, statusCode: $statusCode)';
    } else {
      return 'ApiResponse.error(error: $error, statusCode: $statusCode)';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ApiResponse<T> &&
        other.data == data &&
        other.error == error &&
        other.isSuccess == isSuccess &&
        other.statusCode == statusCode;
  }

  @override
  int get hashCode {
    return data.hashCode ^
        error.hashCode ^
        isSuccess.hashCode ^
        statusCode.hashCode;
  }
}

/// Paginated API Response
class PaginatedApiResponse<T> extends ApiResponse<List<T>> {
  final int? currentPage;
  final int? totalPages;
  final int? totalItems;
  final int? itemsPerPage;
  final bool hasNextPage;
  final bool hasPreviousPage;

  PaginatedApiResponse._({
    required List<T>? data,
    required String? error,
    required bool isSuccess,
    required int? statusCode,
    required Map<String, dynamic>? metadata,
    this.currentPage,
    this.totalPages,
    this.totalItems,
    this.itemsPerPage,
    this.hasNextPage = false,
    this.hasPreviousPage = false,
  }) : super._(
          data: data,
          error: error,
          isSuccess: isSuccess,
          statusCode: statusCode,
          metadata: metadata,
        );

  /// Create a successful paginated response
  factory PaginatedApiResponse.success(
    List<T> data, {
    int? currentPage,
    int? totalPages,
    int? totalItems,
    int? itemsPerPage,
    int? statusCode,
    Map<String, dynamic>? metadata,
  }) {
    final hasNext = currentPage != null &&
        totalPages != null &&
        currentPage < totalPages;
    final hasPrevious = currentPage != null && currentPage > 1;

    return PaginatedApiResponse._(
      data: data,
      error: null,
      isSuccess: true,
      statusCode: statusCode ?? 200,
      metadata: metadata,
      currentPage: currentPage,
      totalPages: totalPages,
      totalItems: totalItems,
      itemsPerPage: itemsPerPage,
      hasNextPage: hasNext,
      hasPreviousPage: hasPrevious,
    );
  }

  /// Create an error paginated response
  factory PaginatedApiResponse.error(
    String error, {
    int? statusCode,
    Map<String, dynamic>? metadata,
  }) {
    return PaginatedApiResponse._(
      data: null,
      error: error,
      isSuccess: false,
      statusCode: statusCode,
      metadata: metadata,
    );
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'PaginatedApiResponse.success(items: ${data?.length}, page: $currentPage/$totalPages)';
    } else {
      return 'PaginatedApiResponse.error(error: $error)';
    }
  }
}
