/// Someone the book owner hands products to, lends money to, or owes money to.
/// A household is one person record with [isHousehold] set, because there is
/// only ever one payer. Who each unit was for is a label on the delivery, not
/// a separate person. See spec-27 dec-5.
class Person {
  const Person({
    required this.id,
    required this.name,
    this.phone,
    this.note,
    this.isHousehold = false,
    this.archived = false,
  });

  final int? id;
  final String name;

  /// Used to open a WhatsApp chat directly through a wa.me link. Without one,
  /// sharing falls back to the system share sheet.
  final String? phone;
  final String? note;
  final bool isHousehold;
  final bool archived;

  Person copyWith({
    int? id,
    String? name,
    String? phone,
    String? note,
    bool? isHousehold,
    bool? archived,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      isHousehold: isHousehold ?? this.isHousehold,
      archived: archived ?? this.archived,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'name': name,
    'phone': phone,
    'note': note,
    'is_household': isHousehold ? 1 : 0,
    'archived': archived ? 1 : 0,
  };

  factory Person.fromMap(Map<String, Object?> map) => Person(
    id: map['id'] as int?,
    name: map['name']! as String,
    phone: map['phone'] as String?,
    note: map['note'] as String?,
    isHousehold: (map['is_household']! as int) == 1,
    archived: (map['archived']! as int) == 1,
  );
}
