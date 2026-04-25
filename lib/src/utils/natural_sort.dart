import 'package:path/path.dart' as p;

int naturalComparePaths(String left, String right) {
  return naturalCompareStrings(p.basename(left), p.basename(right));
}

int naturalCompareStrings(String left, String right) {
  final leftParts = _tokenize(left);
  final rightParts = _tokenize(right);
  final commonLength = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var index = 0; index < commonLength; index++) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftIsDigits = _digitsPattern.hasMatch(leftPart);
    final rightIsDigits = _digitsPattern.hasMatch(rightPart);

    if (leftIsDigits && rightIsDigits) {
      final numericCompare = BigInt.parse(leftPart).compareTo(
        BigInt.parse(rightPart),
      );
      if (numericCompare != 0) {
        return numericCompare;
      }
      final lengthCompare = leftPart.length.compareTo(rightPart.length);
      if (lengthCompare != 0) {
        return lengthCompare;
      }
      continue;
    }

    final insensitiveCompare = leftPart.toLowerCase().compareTo(
      rightPart.toLowerCase(),
    );
    if (insensitiveCompare != 0) {
      return insensitiveCompare;
    }

    final sensitiveCompare = leftPart.compareTo(rightPart);
    if (sensitiveCompare != 0) {
      return sensitiveCompare;
    }
  }

  return leftParts.length.compareTo(rightParts.length);
}

final RegExp _tokenPattern = RegExp(r'\d+|\D+');
final RegExp _digitsPattern = RegExp(r'^\d+$');

List<String> _tokenize(String value) {
  return _tokenPattern
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .where((part) => part.isNotEmpty)
      .toList();
}
