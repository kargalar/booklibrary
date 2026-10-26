part of 'local_database.dart';

class Timestamp implements Comparable<Timestamp> {
  const Timestamp(this.seconds, this.nanoseconds);
  factory Timestamp.fromDate(DateTime date) {
    final micros = date.microsecondsSinceEpoch;
    final seconds = (micros / Duration.microsecondsPerSecond).floor();
    return Timestamp(
      seconds,
      (micros - seconds * Duration.microsecondsPerSecond) * 1000,
    );
  }
  factory Timestamp.now() => Timestamp.fromDate(DateTime.now());
  final int seconds;
  final int nanoseconds;
  int get millisecondsSinceEpoch => seconds * 1000 + nanoseconds ~/ 1000000;
  DateTime toDate() => DateTime.fromMicrosecondsSinceEpoch(
    seconds * Duration.microsecondsPerSecond + nanoseconds ~/ 1000,
  );
  @override
  int compareTo(Timestamp other) {
    final result = seconds.compareTo(other.seconds);
    return result == 0 ? nanoseconds.compareTo(other.nanoseconds) : result;
  }

  @override
  bool operator ==(Object other) =>
      other is Timestamp &&
      seconds == other.seconds &&
      nanoseconds == other.nanoseconds;
  @override
  int get hashCode => Object.hash(seconds, nanoseconds);
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class FieldValue {
  const FieldValue._(this.operation, [this.values = const []]);
  static FieldValue serverTimestamp() => const FieldValue._('timestamp');
  static FieldValue delete() => const FieldValue._('delete');
  static FieldValue arrayUnion(List<Object?> values) =>
      FieldValue._('union', values);
  final String operation;
  final List<Object?> values;
}

Object? encodeLocalValue(Object? value) {
  if (value is Timestamp) {
    return {
      '__type': 'timestamp',
      'seconds': value.seconds,
      'nanoseconds': value.nanoseconds,
    };
  }
  if (value is GeoPoint) {
    return {
      '__type': 'geoPoint',
      'latitude': value.latitude,
      'longitude': value.longitude,
    };
  }
  if (value is DocumentReference) {
    return {'__type': 'reference', 'path': value.path};
  }
  if (value is Uint8List) {
    return {'__type': 'bytes', 'value': base64Encode(value)};
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', encodeLocalValue(item)));
  }
  if (value is Iterable) return value.map(encodeLocalValue).toList();
  return value;
}

Object? decodeLocalValue(Object? value, LocalDatabase store) {
  if (value is List) {
    return value.map((item) => decodeLocalValue(item, store)).toList();
  }
  if (value is Map) {
    switch (value['__type']) {
      case 'timestamp':
        return Timestamp(value['seconds'] as int, value['nanoseconds'] as int);
      case 'geoPoint':
        return GeoPoint(
          (value['latitude'] as num).toDouble(),
          (value['longitude'] as num).toDouble(),
        );
      case 'reference':
        return store.doc(value['path'] as String);
      case 'bytes':
        return base64Decode(value['value'] as String);
    }
    return value.map(
      (key, item) => MapEntry('$key', decodeLocalValue(item, store)),
    );
  }
  return value;
}
