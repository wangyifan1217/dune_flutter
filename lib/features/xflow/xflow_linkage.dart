import 'xflow_bill_cascade.dart';
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
      if (_applyTravelHook(field, values)) continue;
      final expr = field.raw['computeExpr']?.toString();
      if (expr != null && expr.trim().isNotEmpty) {
        values[field.key] = evalExpr(expr, values);
        continue;
      }
      if (field.key == 'remainingInvoiceAmount') {
        final rows = xflowBillSelectedList(values['linkedArBills']);
        values[field.key] = rows.isEmpty
            ? ''
            : xflowBillSelectedRemainingSum(rows, 'invoice').toStringAsFixed(2);
      }
    }
    sumReadonlyTotalFromCardLists(fields, values);
    fillEmptyAmountFromBills(fields, values);
  }

  /// 金额框为空或仍是 0 时，用已选账单剩余合计预填。已填非零金额不覆盖。
  static void fillEmptyAmountFromBills(
    List<XflowField> fields,
    Map<String, dynamic> values,
  ) {
    for (final field in fields) {
      if (field.type == 'computed' || field.key.isEmpty) continue;
      // 只读总金额仍允许预填：付款明细为空时卡片合计会写成 0.00。
      if (field.readonly &&
          field.key != 'totalAmount' &&
          field.key != 'invoiceTotalLimit') {
        continue;
      }
      if (!_isBlankAmount(values[field.key])) continue;
      if (field.key == 'paymentAmount') {
        final rows = xflowBillSelectedList(values['linkedApBills']);
        if (rows.isEmpty) continue;
        values[field.key] = xflowBillSelectedRemainingSum(
          rows,
          'payable',
        ).toStringAsFixed(2);
      } else if (field.key == 'invoiceTotalLimit') {
        final rows = xflowBillSelectedList(values['linkedArBills']);
        if (rows.isEmpty) continue;
        values[field.key] = xflowBillSelectedRemainingSum(
          rows,
          'invoice',
        ).toStringAsFixed(2);
      } else if (field.key == 'totalAmount') {
        final filled = _billRemainingPrefill(fields, values);
        if (filled == null) continue;
        values[field.key] = filled;
      }
    }
  }

  /// 有应付先用应付剩余；否则用应收字段配置的剩余口径（付款看应还、开票看可开）。
  static String? _billRemainingPrefill(
    List<XflowField> fields,
    Map<String, dynamic> values,
  ) {
    final ap = xflowBillSelectedList(values['linkedApBills']);
    if (ap.isNotEmpty) {
      return xflowBillSelectedRemainingSum(
        ap,
        _remainingKindOf(fields, 'linkedApBills'),
      ).toStringAsFixed(2);
    }
    final ar = xflowBillSelectedList(values['linkedArBills']);
    if (ar.isEmpty) return null;
    return xflowBillSelectedRemainingSum(
      ar,
      _remainingKindOf(fields, 'linkedArBills'),
    ).toStringAsFixed(2);
  }

  static String _remainingKindOf(List<XflowField> fields, String key) {
    for (final field in fields) {
      if (field.key == key) {
        return XflowBillCascadeConfig.fromField(field.raw).remainingKind;
      }
    }
    return 'payable';
  }

  static bool _isBlankAmount(dynamic raw) {
    if (raw == null) return true;
    final text = raw.toString().trim();
    if (text.isEmpty) return true;
    final n = double.tryParse(text);
    return n != null && n == 0;
  }

  /// 卡片分组里 money 列之和写入只读 `totalAmount`。无 card 列表时不改动。
  static void sumReadonlyTotalFromCardLists(
    List<XflowField> fields,
    Map<String, dynamic> values,
  ) {
    XflowField? totalField;
    for (final field in fields) {
      if (field.key == 'totalAmount') {
        totalField = field;
        break;
      }
    }
    if (totalField == null || !totalField.readonly) return;
    if (totalField.type == 'computed') return;

    var hasCardMoney = false;
    num sum = 0;
    for (final field in fields) {
      if (!field.isCardDynamicList) continue;
      final moneyKeys = field.moneyColumnKeys;
      if (moneyKeys.isEmpty) continue;
      hasCardMoney = true;
      final groups = values[field.key];
      if (groups is! List) continue;
      for (final row in groups) {
        if (row is! Map) continue;
        for (final key in moneyKeys) {
          sum += _toNumber(row[key]);
        }
      }
    }
    if (!hasCardMoney) return;
    values['totalAmount'] = sum.toStringAsFixed(2);
  }

  /// 差旅申请的天数、标题、住宿标准和预订渠道。返回 true 表示该 hook 已处理。
  static bool _applyTravelHook(XflowField field, Map<String, dynamic> values) {
    final hook = field.raw['hook']?.toString() ?? '';
    switch (hook) {
      case 'inclusiveDays':
        _writeHook(values, field.key, _daySpanLabel(field, values, inclusive: true));
        return true;
      case 'hotelNights':
        final nights = values['needHotel']?.toString() == '是'
            ? _daySpanLabel(field, values, inclusive: false)
            : '';
        _writeHook(values, field.key, nights);
        return true;
      case 'hotelStandard':
        final standard = values['needHotel']?.toString() == '是'
            ? _hotelStandardLabel(values)
            : '';
        _writeHook(values, field.key, standard);
        return true;
      case 'travelTitle':
        _writeHook(values, field.key, _travelTitleLabel(values));
        return true;
      case 'bookingChannel':
        _writeHook(values, field.key, _bookingChannelLabel(values));
        return true;
      default:
        return false;
    }
  }

  static void _writeHook(Map<String, dynamic> values, String key, String value) {
    if (value.isEmpty) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }

  static String _daySpanLabel(
    XflowField field,
    Map<String, dynamic> values, {
    required bool inclusive,
  }) {
    final start = _parseDay(values[_metaString(field, 'from', 'startDate')]);
    final end = _parseDay(values[_metaString(field, 'to', 'endDate')]);
    if (start == null || end == null) return '';
    final days = DateTime(end.year, end.month, end.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
    if (days < 0) return '';
    final count = inclusive ? days + 1 : days;
    return '$count${_metaString(field, 'suffix', '天')}';
  }

  static String _hotelStandardLabel(Map<String, dynamic> values) {
    if ('${values['companions'] ?? ''}'.trim().isNotEmpty) {
      return '同性别拼房标准：300元/人/晚';
    }
    return '单人差旅标准：450元/晚';
  }

  static String _travelTitleLabel(Map<String, dynamic> values) {
    final unit = '${values['visitUnit'] ?? ''}'.trim();
    var reason = '${values['travelReason'] ?? ''}'.trim();
    final reasonChars = reason.runes.toList();
    if (reasonChars.length > 30) {
      reason = '${String.fromCharCodes(reasonChars.take(30))}...';
    }
    if (unit.isEmpty && reason.isEmpty) return '';
    if (unit.isEmpty) return reason;
    if (reason.isEmpty) return unit;
    return '$unit - $reason';
  }

  static String _bookingChannelLabel(Map<String, dynamic> values) {
    final rows = values['itineraryItems'];
    var hasPlatform = false;
    var hasSelf = false;
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map) continue;
        switch ('${row['bookingMethod'] ?? ''}'.trim()) {
          case '自行预订':
            hasSelf = true;
            break;
          case '公司商旅平台':
            hasPlatform = true;
            break;
        }
      }
    }
    if (hasSelf) return '自行预订';
    if (hasPlatform) return '携程';
    return '';
  }

  static String _metaString(XflowField field, String key, String fallback) {
    final meta = field.raw['meta'];
    if (meta is Map) {
      final text = '${meta[key] ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static DateTime? _parseDay(dynamic raw) {
    final text = '${raw ?? ''}'.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
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
