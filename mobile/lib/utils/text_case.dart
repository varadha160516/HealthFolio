/// Capitalizes just the first letter — used for single-word status/relationship values that come
/// back from the API in lowercase ('child', 'self', 'male', 'yes', ...) but should read as proper
/// words in the UI ('Child', 'Self', 'Male', 'Yes').
String capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Same as [capitalizeFirst], but passes through null — for the many optional profile fields
/// (sex, organ donor status, ...) that are `String?` all the way from the API response.
String? capitalizeFirstOrNull(String? s) => s == null ? null : capitalizeFirst(s);
