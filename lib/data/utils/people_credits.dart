/// A person may have several server credits (especially voice actors). Present
/// one person card and retain the distinct character names in its role text.
List<Map<String, dynamic>> mergePeopleCredits(
  Iterable<Map<String, dynamic>> people,
) {
  final merged = <String, Map<String, dynamic>>{};
  final roles = <String, Set<String>>{};
  for (final person in people) {
    final id = person['Id']?.toString().trim() ?? '';
    final name = person['Name']?.toString().trim() ?? '';
    if (id.isEmpty && name.isEmpty) continue;
    final key = id.isEmpty ? 'name:${name.toLowerCase()}' : 'id:$id';
    merged.putIfAbsent(key, () => {...person});
    final role = person['Role']?.toString().trim() ?? '';
    if (role.isNotEmpty) (roles[key] ??= {}).add(role);
  }
  return [
    for (final entry in merged.entries)
      {
        ...entry.value,
        if (roles[entry.key]?.isNotEmpty ?? false)
          'Role': roles[entry.key]!.join(' / '),
      },
  ];
}
