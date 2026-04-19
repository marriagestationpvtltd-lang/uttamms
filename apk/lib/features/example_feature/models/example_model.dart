/// Example Data Model
///
/// Template for creating feature-specific data models.
/// Shows proper JSON serialization and null safety.

class ExampleModel {
  final String id;
  final String title;
  final String? description;
  final DateTime createdAt;
  final bool isActive;

  ExampleModel({
    required this.id,
    required this.title,
    this.description,
    required this.createdAt,
    this.isActive = true,
  });

  /// Create model from JSON response
  factory ExampleModel.fromJson(Map<String, dynamic> json) {
    return ExampleModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      description: json['description']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isActive: json['is_active'] == true || json['is_active'] == 1,
    );
  }

  /// Convert model to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      if (description != null) 'description': description,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }

  /// Create a copy with modified fields
  ExampleModel copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return ExampleModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'ExampleModel(id: $id, title: $title, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ExampleModel &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.createdAt == createdAt &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        description.hashCode ^
        createdAt.hashCode ^
        isActive.hashCode;
  }
}
