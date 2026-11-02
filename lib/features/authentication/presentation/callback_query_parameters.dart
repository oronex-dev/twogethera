/// Combines the Flutter route query with a query on the outer browser URL.
///
/// Hash routing normally places callback values inside the fragment, where
/// GoRouter exposes them on [routeUri]. Some redirect handlers append values
/// before the fragment instead; those are visible on [browserUri]. Keeping
/// both occurrences lets the callback's existing strict shape check reject
/// ambiguous or duplicated parameters.
Map<String, List<String>> callbackQueryParameters(
  Uri routeUri, {
  Uri? browserUri,
}) {
  final routeParameters = routeUri.queryParametersAll;
  final browserParameters = browserUri?.queryParametersAll ?? const {};
  if (routeParameters.isEmpty) return browserParameters;
  if (browserParameters.isEmpty) return routeParameters;

  final merged = <String, List<String>>{
    for (final entry in routeParameters.entries) entry.key: [...entry.value],
  };
  for (final entry in browserParameters.entries) {
    merged.update(
      entry.key,
      (existing) => [...existing, ...entry.value],
      ifAbsent: () => [...entry.value],
    );
  }
  return merged;
}
