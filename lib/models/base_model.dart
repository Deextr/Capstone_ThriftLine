/// Base contract for data models with JSON serialization.
abstract class BaseModel {
  const BaseModel();
  Map<String, dynamic> toJson();

  @override
  String toString() => toJson().toString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaseModel && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
