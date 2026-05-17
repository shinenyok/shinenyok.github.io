import 'dart:convert';

class JsonToDartGenerator {
  String generate({required String source, required String rootClassName}) {
    final decoded = jsonDecode(source);
    final normalizedName = _toPascalCase(rootClassName, fallback: 'RootModel');
    final rootSamples = switch (decoded) {
      Map<String, dynamic>() => [decoded],
      List<dynamic>()
          when decoded.whereType<Map<String, dynamic>>().isNotEmpty =>
        decoded.whereType<Map<String, dynamic>>().toList(),
      _ => throw const FormatException('JSON 根节点需要是对象，或对象数组。'),
    };

    final registry = _ClassRegistry();
    registry.buildClass(normalizedName, rootSamples);
    return registry.render();
  }
}

class _ClassRegistry {
  final Map<String, _ClassSpec> _classes = {};

  _ClassSpec buildClass(
    String requestedName,
    List<Map<String, dynamic>> samples,
  ) {
    final className = _uniqueClassName(requestedName);
    final mergedKeys = <String>{};
    for (final sample in samples) {
      mergedKeys.addAll(sample.keys);
    }

    final fields = <_FieldSpec>[];
    for (final key in mergedKeys) {
      final values = samples.map((sample) => sample[key]).toList();
      final isNullable =
          samples.any((sample) => !sample.containsKey(key)) ||
          values.any((value) => value == null);
      final fieldName = _safeFieldName(key);
      final typeRef = _inferType(key, values, className);
      fields.add(
        _FieldSpec(
          jsonKey: key,
          name: fieldName,
          type: typeRef,
          isNullable: isNullable,
        ),
      );
    }

    fields.sort((a, b) => a.name.compareTo(b.name));
    final spec = _ClassSpec(name: className, fields: fields);
    _classes[className] = spec;
    return spec;
  }

  String render() {
    final buffer = StringBuffer();
    for (final spec in _classes.values.toList().reversed) {
      if (buffer.isNotEmpty) {
        buffer.writeln();
      }
      buffer.write(spec.render());
    }
    return buffer.toString();
  }

  _TypeRef _inferType(
    String key,
    List<dynamic> values,
    String parentClassName,
  ) {
    final nonNullValues = values.where((value) => value != null).toList();
    if (nonNullValues.isEmpty) {
      return const _TypeRef('dynamic');
    }

    if (nonNullValues.every((value) => value is bool)) {
      return const _TypeRef('bool');
    }
    if (nonNullValues.every((value) => value is int)) {
      return const _TypeRef('int');
    }
    if (nonNullValues.every((value) => value is num)) {
      return const _TypeRef('double');
    }
    if (nonNullValues.every((value) => value is String)) {
      return const _TypeRef('String');
    }
    if (nonNullValues.every((value) => value is Map<String, dynamic>)) {
      final nestedName = _toPascalCase(key, fallback: '${parentClassName}Item');
      final nestedClass = buildClass(
        nestedName,
        nonNullValues.cast<Map<String, dynamic>>(),
      );
      return _TypeRef(nestedClass.name, isModel: true);
    }
    if (nonNullValues.every((value) => value is List<dynamic>)) {
      final nestedValues = nonNullValues
          .cast<List<dynamic>>()
          .expand((value) => value)
          .toList();
      if (nestedValues.isEmpty) {
        return const _TypeRef('List<dynamic>', isList: true);
      }
      final nestedType = _inferType(
        _singularize(key),
        nestedValues,
        parentClassName,
      );
      return _TypeRef(
        'List<${nestedType.dartType}>',
        isList: true,
        itemType: nestedType,
      );
    }

    return const _TypeRef('dynamic');
  }

  String _uniqueClassName(String requestedName) {
    final baseName = _toPascalCase(requestedName, fallback: 'GeneratedModel');
    if (!_classes.containsKey(baseName)) {
      return baseName;
    }

    var suffix = 2;
    while (_classes.containsKey('$baseName$suffix')) {
      suffix++;
    }
    return '$baseName$suffix';
  }
}

class _ClassSpec {
  const _ClassSpec({required this.name, required this.fields});

  final String name;
  final List<_FieldSpec> fields;

  String render() {
    final buffer = StringBuffer()..writeln('class $name {');

    for (final field in fields) {
      buffer.writeln('  final ${field.declarationType} ${field.name};');
    }

    buffer
      ..writeln()
      ..writeln('  const $name({');
    for (final field in fields) {
      final required = field.isNullable ? '' : 'required ';
      buffer.writeln('    ${required}this.${field.name},');
    }
    buffer
      ..writeln('  });')
      ..writeln()
      ..writeln('  factory $name.fromJson(Map<String, dynamic> json) {')
      ..writeln('    return $name(');
    for (final field in fields) {
      buffer.writeln('      ${field.name}: ${field.fromJsonExpression},');
    }
    buffer
      ..writeln('    );')
      ..writeln('  }')
      ..writeln()
      ..writeln('  Map<String, dynamic> toJson() {')
      ..writeln('    return {');
    for (final field in fields) {
      buffer.writeln("      '${field.jsonKey}': ${field.toJsonExpression},");
    }
    buffer
      ..writeln('    };')
      ..writeln('  }')
      ..writeln('}');

    return buffer.toString();
  }
}

class _FieldSpec {
  const _FieldSpec({
    required this.jsonKey,
    required this.name,
    required this.type,
    required this.isNullable,
  });

  final String jsonKey;
  final String name;
  final _TypeRef type;
  final bool isNullable;

  String get declarationType =>
      isNullable ? '${type.dartType}?' : type.dartType;

  String get fromJsonExpression {
    final keyAccess = "json['$jsonKey']";
    return type.fromJson(keyAccess, isNullable: isNullable);
  }

  String get toJsonExpression => type.toJson(name, isNullable: isNullable);
}

class _TypeRef {
  const _TypeRef(
    this.dartType, {
    this.isModel = false,
    this.isList = false,
    this.itemType,
  });

  final String dartType;
  final bool isModel;
  final bool isList;
  final _TypeRef? itemType;

  String fromJson(String source, {required bool isNullable}) {
    if (isList) {
      final item = itemType ?? const _TypeRef('dynamic');
      final cast = isNullable
          ? '($source as List<dynamic>?)'
          : '($source as List<dynamic>)';
      final mapped = item.dartType == 'dynamic'
          ? 'item'
          : item.fromJson('item', isNullable: false);
      final expression =
          '$cast${isNullable ? '?' : ''}.map((item) => $mapped).toList()';
      return expression;
    }
    if (isModel) {
      final expression = '$dartType.fromJson($source as Map<String, dynamic>)';
      if (isNullable) {
        return '$source == null ? null : $expression';
      }
      return expression;
    }
    return switch (dartType) {
      'double' =>
        isNullable
            ? '($source as num?)?.toDouble()'
            : '($source as num).toDouble()',
      'dynamic' => source,
      _ =>
        '$source as ${isNullable ? '$declarationTypeForCast?' : declarationTypeForCast}',
    };
  }

  String toJson(String source, {required bool isNullable}) {
    if (isList) {
      final item = itemType ?? const _TypeRef('dynamic');
      if (!item.isModel) {
        return source;
      }
      final access = isNullable ? '$source?' : source;
      return '$access.map((item) => item.toJson()).toList()';
    }
    if (isModel) {
      return isNullable ? '$source?.toJson()' : '$source.toJson()';
    }
    return source;
  }

  String get declarationTypeForCast {
    return switch (dartType) {
      'List<dynamic>' => 'List<dynamic>',
      _ => dartType,
    };
  }
}

String _singularize(String value) {
  if (value.endsWith('ies') && value.length > 3) {
    return '${value.substring(0, value.length - 3)}y';
  }
  if (value.endsWith('s') && value.length > 1) {
    return value.substring(0, value.length - 1);
  }
  return value;
}

String _toPascalCase(String value, {required String fallback}) {
  final parts = value
      .trim()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return fallback;
  }
  final joined = parts.map((part) {
    final lower = part.substring(0, 1).toUpperCase() + part.substring(1);
    return lower;
  }).join();
  if (RegExp(r'^[0-9]').hasMatch(joined)) {
    return '$fallback$joined';
  }
  return joined;
}

String _safeFieldName(String key) {
  final parts = key
      .trim()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  final base = parts.isEmpty
      ? 'value'
      : parts.first.toLowerCase() +
            parts
                .skip(1)
                .map(
                  (part) =>
                      part.substring(0, 1).toUpperCase() + part.substring(1),
                )
                .join();
  final normalized = RegExp(r'^[0-9]').hasMatch(base) ? 'field$base' : base;
  return _dartKeywords.contains(normalized) ? '${normalized}Value' : normalized;
}

const Set<String> _dartKeywords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};
