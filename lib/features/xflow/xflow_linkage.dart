import 'xflow_models.dart';

/// 原生 XFlow 表单的联动 / 计算逻辑。
///
/// 与前端原型 `assets/prototype/xflow_linkage.js` 及 admin 端
/// `admin-web/src/utils/xflowLinkage.ts` 保持一致：当用户填写字段时，
/// 需要同步重算「计算只读」字段（如印花税 `stampTax`、`computeExpr`）以及
/// layout.linkage 中的 `compute` 规则，否则原生表单不会自动计算。
class XflowLinkage {
  const XflowLinkage._();

  /// 重算所有派生值。会就地修改 [values]。
  ///
  /// 1. 先跑 layout.linkage 的 `compute` 规则；
  /// 2. 再重算所有 `computed` 字段（`hook: stampTax` 或 `computeExpr`）。
  static void recompute(
    List<XflowField> fields,
    Map<String, dynamic> layout,
    Map<String, dynamic> values,
  ) {
    runLinkage(layout, values);
    for (final field in fields) {
      if (field.type != 'computed' || field.key.isEmpty) continue;
      final hook = field.raw['hook']?.toString();
      if (hook == 'stampTax') {
        values[field.key] = stampTax(values);
        continue;
      }
      final expr = field.raw['computeExpr']?.toString();
      if (expr != null && expr.trim().isNotEmpty) {
        values[field.key] = evalExpr(expr, values);
      }
    }
  }

  /// 印花税：按目标月规模（万元）的万分之三计算，保留两位小数。
  static String stampTax(Map<String, dynamic> values) {
    final scale = _toNumber(values['targetMonthlyScaleWan']);
    return (scale * 0.0003).toStringAsFixed(2);
  }

  /// 执行 layout.linkage 中的联动规则（当前支持 `compute`）。
  static void runLinkage(Map<String, dynamic> layout, Map<String, dynamic> values) {
    final linkage = layout['linkage'];
    if (linkage is! List) return;
    for (final rule in linkage) {
      if (rule is! Map) continue;
      final type = rule['type']?.toString();
      if (type == 'compute') {
        final target = rule['target']?.toString();
        final expr = rule['expr']?.toString();
        if (target != null && target.isNotEmpty && expr != null && expr.trim().isNotEmpty) {
          values[target] = evalExpr(expr, values);
        }
      }
    }
  }

  /// 计算简单算术表达式（如 `targetMonthlyScaleWan * 0.0003`）。
  ///
  /// 表达式中的标识符会被替换为对应字段的数值（无法解析时取 0），
  /// 支持 `+ - * / ( )` 及一元负号。失败返回 `—`。
  static String evalExpr(String expr, Map<String, dynamic> values) {
    if (expr.trim().isEmpty) return '';
    try {
      final result = _ExprEvaluator(expr, values).evaluate();
      if (result.isNaN || result.isInfinite) return '—';
      return result.toStringAsFixed(2);
    } catch (_) {
      return '—';
    }
  }

  static double _toNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

/// 极简递归下降算术表达式求值器，仅支持 `+ - * / ( )` 与标识符 / 数字。
class _ExprEvaluator {
  _ExprEvaluator(this._src, this._values);

  final String _src;
  final Map<String, dynamic> _values;
  int _pos = 0;

  double evaluate() {
    final value = _parseExpression();
    _skipWhitespace();
    if (_pos != _src.length) {
      throw const FormatException('unexpected trailing characters');
    }
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWhitespace();
      final op = _peek();
      if (op == '+') {
        _pos++;
        value += _parseTerm();
      } else if (op == '-') {
        _pos++;
        value -= _parseTerm();
      } else {
        break;
      }
    }
    return value;
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipWhitespace();
      final op = _peek();
      if (op == '*') {
        _pos++;
        value *= _parseFactor();
      } else if (op == '/') {
        _pos++;
        value /= _parseFactor();
      } else {
        break;
      }
    }
    return value;
  }

  double _parseFactor() {
    _skipWhitespace();
    final ch = _peek();
    if (ch == '+') {
      _pos++;
      return _parseFactor();
    }
    if (ch == '-') {
      _pos++;
      return -_parseFactor();
    }
    if (ch == '(') {
      _pos++;
      final value = _parseExpression();
      _skipWhitespace();
      if (_peek() != ')') throw const FormatException('missing closing paren');
      _pos++;
      return value;
    }
    if (_isDigit(ch) || ch == '.') {
      return _parseNumber();
    }
    if (_isIdentStart(ch)) {
      return _parseIdentifier();
    }
    throw FormatException('unexpected char at $_pos');
  }

  double _parseNumber() {
    final start = _pos;
    while (_pos < _src.length && (_isDigit(_src[_pos]) || _src[_pos] == '.')) {
      _pos++;
    }
    return double.parse(_src.substring(start, _pos));
  }

  double _parseIdentifier() {
    final start = _pos;
    while (_pos < _src.length && _isIdentPart(_src[_pos])) {
      _pos++;
    }
    final name = _src.substring(start, _pos);
    return XflowLinkage._toNumber(_values[name]);
  }

  void _skipWhitespace() {
    while (_pos < _src.length && _src[_pos].trim().isEmpty) {
      _pos++;
    }
  }

  String _peek() => _pos < _src.length ? _src[_pos] : '';

  bool _isDigit(String ch) => ch.isNotEmpty && ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  bool _isIdentStart(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || ch == '_' || c > 127;
  }

  bool _isIdentPart(String ch) => _isIdentStart(ch) || _isDigit(ch);
}
