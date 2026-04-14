/// 教室ユーティリティ
/// families.children[].classrooms（配列）と旧 classroom（文字列）の両方に対応

/// childドキュメントから教室リストを取得（新旧どちらの形式にも対応）
List<String> getChildClassrooms(Map<String, dynamic> child) {
  // 新形式: classrooms（配列）
  final classrooms = child['classrooms'];
  if (classrooms is List && classrooms.isNotEmpty) {
    return classrooms.map((e) => e.toString()).toList();
  }
  // 旧形式: classroom（文字列）
  final classroom = child['classroom'] as String? ?? '';
  if (classroom.isNotEmpty) return [classroom];
  return [];
}

/// childが指定教室に所属しているか
bool childBelongsToClassroom(Map<String, dynamic> child, String classroom) {
  return getChildClassrooms(child).contains(classroom);
}

/// 教室リストの表示用文字列
String classroomsDisplayText(Map<String, dynamic> child) {
  return getChildClassrooms(child).join(', ');
}
