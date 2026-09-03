class TravelCity {
  const TravelCity({
    required this.name,
    required this.province,
    required this.lon,
    required this.lat,
  });
  final String name;
  final String province;
  final double lon;
  final double lat;
}

enum TravelKind { flight, train, hotel, ground }

extension TravelKindX on TravelKind {
  String get label => switch (this) {
        TravelKind.flight => '飞机',
        TravelKind.train => '火车',
        TravelKind.hotel => '酒店',
        TravelKind.ground => '用车',
      };
}

TravelKind travelKindFrom(String raw) {
  return switch (raw.trim()) {
    'train' => TravelKind.train,
    'hotel' => TravelKind.hotel,
    'ground' => TravelKind.ground,
    _ => TravelKind.flight,
  };
}

class TravelLeg {
  const TravelLeg({
    required this.from,
    required this.to,
    required this.date,
    required this.amount,
    this.rebookFee = 0,
    this.kind = TravelKind.flight,
    this.orderId = '',
    this.shared = false,
    this.originProvince = '',
    this.destProvince = '',
  });
  final String from;
  final String to;
  final String date;
  /// 分摊后金额，单位分。
  final int amount;
  /// 整单改签手续费，单位分；同行人各行都带同一笔全额。
  final int rebookFee;
  final TravelKind kind;
  final String orderId;
  final bool shared;
  final String originProvince;
  final String destProvince;

  bool get samePlace => from.isNotEmpty && from == to;
}

class TravelEmployee {
  const TravelEmployee({
    required this.id,
    required this.name,
    required this.dept,
    required this.cost,
    this.fee = 0,
    required this.trips,
    required this.lastTrip,
    required this.provinces,
    required this.legs,
    this.provinceVisits = const {},
  });
  final String id;
  final String name;
  final String dept;
  /// 可见范围内分摊后合计，单位分。
  final int cost;
  /// 该员工名下订单的改签手续费合计（按订单去重），单位分。
  final int fee;
  final int trips;
  final String lastTrip;
  final List<String> provinces;
  final List<TravelLeg> legs;
  final Map<String, int> provinceVisits;

  int visitCount(String province) => provinceVisits[province] ?? 0;

  String provinceChip(String province) {
    final n = visitCount(province);
    return n > 0 ? '$province 停留$n次' : province;
  }
}

const travelCities = <String, TravelCity>{
  '北京': TravelCity(name: '北京', province: '北京', lon: 116.40, lat: 39.90),
  '天津': TravelCity(name: '天津', province: '天津', lon: 117.20, lat: 39.13),
  '上海': TravelCity(name: '上海', province: '上海', lon: 121.47, lat: 31.23),
  '重庆': TravelCity(name: '重庆', province: '重庆', lon: 106.55, lat: 29.56),
  '石家庄': TravelCity(name: '石家庄', province: '河北', lon: 114.51, lat: 38.04),
  '唐山': TravelCity(name: '唐山', province: '河北', lon: 118.18, lat: 39.63),
  '保定': TravelCity(name: '保定', province: '河北', lon: 115.46, lat: 38.87),
  '邯郸': TravelCity(name: '邯郸', province: '河北', lon: 114.49, lat: 36.61),
  '廊坊': TravelCity(name: '廊坊', province: '河北', lon: 116.70, lat: 39.52),
  '秦皇岛': TravelCity(name: '秦皇岛', province: '河北', lon: 119.60, lat: 39.94),
  '太原': TravelCity(name: '太原', province: '山西', lon: 112.55, lat: 37.87),
  '大同': TravelCity(name: '大同', province: '山西', lon: 113.30, lat: 40.08),
  '呼和浩特': TravelCity(name: '呼和浩特', province: '内蒙古', lon: 111.75, lat: 40.84),
  '包头': TravelCity(name: '包头', province: '内蒙古', lon: 109.84, lat: 40.66),
  '鄂尔多斯': TravelCity(name: '鄂尔多斯', province: '内蒙古', lon: 109.78, lat: 39.61),
  '沈阳': TravelCity(name: '沈阳', province: '辽宁', lon: 123.43, lat: 41.80),
  '大连': TravelCity(name: '大连', province: '辽宁', lon: 121.62, lat: 38.92),
  '长春': TravelCity(name: '长春', province: '吉林', lon: 125.32, lat: 43.82),
  '吉林': TravelCity(name: '吉林', province: '吉林', lon: 126.55, lat: 43.84),
  '哈尔滨': TravelCity(name: '哈尔滨', province: '黑龙江', lon: 126.53, lat: 45.80),
  '齐齐哈尔': TravelCity(name: '齐齐哈尔', province: '黑龙江', lon: 123.95, lat: 47.35),
  '南京': TravelCity(name: '南京', province: '江苏', lon: 118.78, lat: 32.06),
  '苏州': TravelCity(name: '苏州', province: '江苏', lon: 120.62, lat: 31.32),
  '无锡': TravelCity(name: '无锡', province: '江苏', lon: 120.30, lat: 31.57),
  '常州': TravelCity(name: '常州', province: '江苏', lon: 119.97, lat: 31.81),
  '南通': TravelCity(name: '南通', province: '江苏', lon: 120.86, lat: 32.01),
  '徐州': TravelCity(name: '徐州', province: '江苏', lon: 117.18, lat: 34.26),
  '扬州': TravelCity(name: '扬州', province: '江苏', lon: 119.42, lat: 32.39),
  '杭州': TravelCity(name: '杭州', province: '浙江', lon: 120.16, lat: 30.25),
  '宁波': TravelCity(name: '宁波', province: '浙江', lon: 121.54, lat: 29.87),
  '温州': TravelCity(name: '温州', province: '浙江', lon: 120.70, lat: 28.00),
  '嘉兴': TravelCity(name: '嘉兴', province: '浙江', lon: 120.76, lat: 30.75),
  '绍兴': TravelCity(name: '绍兴', province: '浙江', lon: 120.58, lat: 30.00),
  '金华': TravelCity(name: '金华', province: '浙江', lon: 119.65, lat: 29.08),
  '义乌': TravelCity(name: '义乌', province: '浙江', lon: 120.07, lat: 29.31),
  '合肥': TravelCity(name: '合肥', province: '安徽', lon: 117.23, lat: 31.82),
  '芜湖': TravelCity(name: '芜湖', province: '安徽', lon: 118.38, lat: 31.33),
  '黄山': TravelCity(name: '黄山', province: '安徽', lon: 118.34, lat: 29.71),
  '福州': TravelCity(name: '福州', province: '福建', lon: 119.30, lat: 26.08),
  '厦门': TravelCity(name: '厦门', province: '福建', lon: 118.09, lat: 24.48),
  '泉州': TravelCity(name: '泉州', province: '福建', lon: 118.68, lat: 24.87),
  '南昌': TravelCity(name: '南昌', province: '江西', lon: 115.86, lat: 28.68),
  '赣州': TravelCity(name: '赣州', province: '江西', lon: 114.93, lat: 25.83),
  '济南': TravelCity(name: '济南', province: '山东', lon: 117.00, lat: 36.67),
  '青岛': TravelCity(name: '青岛', province: '山东', lon: 120.38, lat: 36.07),
  '烟台': TravelCity(name: '烟台', province: '山东', lon: 121.39, lat: 37.54),
  '潍坊': TravelCity(name: '潍坊', province: '山东', lon: 119.16, lat: 36.71),
  '临沂': TravelCity(name: '临沂', province: '山东', lon: 118.36, lat: 35.10),
  '郑州': TravelCity(name: '郑州', province: '河南', lon: 113.65, lat: 34.76),
  '洛阳': TravelCity(name: '洛阳', province: '河南', lon: 112.45, lat: 34.62),
  '武汉': TravelCity(name: '武汉', province: '湖北', lon: 114.31, lat: 30.59),
  '宜昌': TravelCity(name: '宜昌', province: '湖北', lon: 111.29, lat: 30.69),
  '襄阳': TravelCity(name: '襄阳', province: '湖北', lon: 112.12, lat: 32.01),
  '长沙': TravelCity(name: '长沙', province: '湖南', lon: 112.98, lat: 28.19),
  '株洲': TravelCity(name: '株洲', province: '湖南', lon: 113.13, lat: 27.83),
  '张家界': TravelCity(name: '张家界', province: '湖南', lon: 110.48, lat: 29.12),
  '广州': TravelCity(name: '广州', province: '广东', lon: 113.26, lat: 23.13),
  '深圳': TravelCity(name: '深圳', province: '广东', lon: 114.06, lat: 22.54),
  '佛山': TravelCity(name: '佛山', province: '广东', lon: 113.12, lat: 23.02),
  '东莞': TravelCity(name: '东莞', province: '广东', lon: 113.75, lat: 23.05),
  '珠海': TravelCity(name: '珠海', province: '广东', lon: 113.58, lat: 22.27),
  '中山': TravelCity(name: '中山', province: '广东', lon: 113.38, lat: 22.52),
  '惠州': TravelCity(name: '惠州', province: '广东', lon: 114.42, lat: 23.11),
  '汕头': TravelCity(name: '汕头', province: '广东', lon: 116.68, lat: 23.35),
  '湛江': TravelCity(name: '湛江', province: '广东', lon: 110.36, lat: 21.27),
  '南宁': TravelCity(name: '南宁', province: '广西', lon: 108.37, lat: 22.82),
  '桂林': TravelCity(name: '桂林', province: '广西', lon: 110.29, lat: 25.27),
  '柳州': TravelCity(name: '柳州', province: '广西', lon: 109.43, lat: 24.33),
  '北海': TravelCity(name: '北海', province: '广西', lon: 109.12, lat: 21.48),
  '海口': TravelCity(name: '海口', province: '海南', lon: 110.35, lat: 20.02),
  '三亚': TravelCity(name: '三亚', province: '海南', lon: 109.51, lat: 18.25),
  '成都': TravelCity(name: '成都', province: '四川', lon: 104.07, lat: 30.67),
  '绵阳': TravelCity(name: '绵阳', province: '四川', lon: 104.68, lat: 31.47),
  '贵阳': TravelCity(name: '贵阳', province: '贵州', lon: 106.63, lat: 26.65),
  '遵义': TravelCity(name: '遵义', province: '贵州', lon: 106.93, lat: 27.73),
  '昆明': TravelCity(name: '昆明', province: '云南', lon: 102.71, lat: 25.04),
  '大理': TravelCity(name: '大理', province: '云南', lon: 100.23, lat: 25.60),
  '丽江': TravelCity(name: '丽江', province: '云南', lon: 100.23, lat: 26.88),
  '西双版纳': TravelCity(name: '西双版纳', province: '云南', lon: 100.80, lat: 22.01),
  '拉萨': TravelCity(name: '拉萨', province: '西藏', lon: 91.14, lat: 29.65),
  '西安': TravelCity(name: '西安', province: '陕西', lon: 108.94, lat: 34.34),
  '咸阳': TravelCity(name: '咸阳', province: '陕西', lon: 108.71, lat: 34.33),
  '兰州': TravelCity(name: '兰州', province: '甘肃', lon: 103.83, lat: 36.06),
  '敦煌': TravelCity(name: '敦煌', province: '甘肃', lon: 94.66, lat: 40.14),
  '西宁': TravelCity(name: '西宁', province: '青海', lon: 101.78, lat: 36.62),
  '银川': TravelCity(name: '银川', province: '宁夏', lon: 106.23, lat: 38.49),
  '乌鲁木齐': TravelCity(name: '乌鲁木齐', province: '新疆', lon: 87.62, lat: 43.83),
  '喀什': TravelCity(name: '喀什', province: '新疆', lon: 75.99, lat: 39.47),
  '香港': TravelCity(name: '香港', province: '香港', lon: 114.17, lat: 22.32),
  '澳门': TravelCity(name: '澳门', province: '澳门', lon: 113.54, lat: 22.19),
  '台北': TravelCity(name: '台北', province: '台湾', lon: 121.57, lat: 25.04),
  '高雄': TravelCity(name: '高雄', province: '台湾', lon: 120.31, lat: 22.62),
  '虹桥': TravelCity(name: '虹桥', province: '上海', lon: 121.32, lat: 31.19),
  '浦东': TravelCity(name: '浦东', province: '上海', lon: 121.54, lat: 31.22),
  '亦庄': TravelCity(name: '亦庄', province: '北京', lon: 116.50, lat: 39.80),
  '大兴': TravelCity(name: '大兴', province: '北京', lon: 116.34, lat: 39.73),
  '首都': TravelCity(name: '首都', province: '北京', lon: 116.60, lat: 40.08),
};

/// 站名/常用别称 → 城市，用来从旧用车地址（如「汉口火车站J口」）找回落点。
const _travelStationAlias = <String, String>{
  '北京西': '北京',
  '北京南': '北京',
  '北京北': '北京',
  '北京东': '北京',
  '北京站': '北京',
  '上海虹桥': '上海',
  '上海南': '上海',
  '上海西': '上海',
  '上海站': '上海',
  '广州南': '广州',
  '广州东': '广州',
  '广州北': '广州',
  '广州站': '广州',
  '深圳北': '深圳',
  '深圳东': '深圳',
  '深圳西': '深圳',
  '杭州东': '杭州',
  '杭州南': '杭州',
  '杭州西': '杭州',
  '南京南': '南京',
  '武汉站': '武汉',
  '汉口': '武汉',
  '武昌': '武汉',
  '长沙南': '长沙',
  '成都东': '成都',
  '成都南': '成都',
  '西安北': '西安',
  '郑州东': '郑州',
  '济南西': '济南',
  '合肥南': '合肥',
  '南昌西': '南昌',
  '重庆北': '重庆',
  '重庆西': '重庆',
  '天津西': '天津',
  '天津南': '天津',
  '厦门北': '厦门',
  '福州南': '福州',
  '贵阳北': '贵阳',
  '昆明南': '昆明',
  '南宁东': '南宁',
  '哈尔滨西': '哈尔滨',
  '沈阳北': '沈阳',
  '长春西': '长春',
  '太原南': '太原',
  '兰州西': '兰州',
};

TravelCity? travelCityOf(String name) {
  final n = name.trim();
  if (n.isEmpty) return null;
  final direct = travelCities[n];
  if (direct != null) return direct;
  if (n.endsWith('市') && n.length > 1) {
    final city = travelCities[n.substring(0, n.length - 1)];
    if (city != null) return city;
  }
  var bestCity = '';
  var bestLen = 0;
  for (final e in _travelStationAlias.entries) {
    if (n.contains(e.key) && e.key.length > bestLen) {
      bestCity = e.value;
      bestLen = e.key.length;
    }
  }
  if (bestCity.isEmpty) return null;
  return travelCities[bestCity];
}

List<String> provincesFromLegs(List<TravelLeg> legs) {
  final s = <String>{};
  for (final l in legs) {
    if (l.kind == TravelKind.ground) {
      if (l.originProvince.isNotEmpty) s.add(l.originProvince);
      final a = travelCityOf(l.from);
      if (a != null) s.add(a.province);
      continue;
    }
    for (final p in [l.originProvince, l.destProvince]) {
      if (p.isNotEmpty) s.add(p);
    }
    final a = travelCityOf(l.from);
    final b = travelCityOf(l.to);
    if (a != null) s.add(a.province);
    if (b != null) s.add(b.province);
  }
  return s.toList();
}

String _groupInt(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// [fen] 为分。整数元不显示小数，否则保留两位。
String formatYuan(int fen) {
  final negative = fen < 0;
  final absFen = fen.abs();
  final yuan = absFen / 100.0;
  final String body;
  if (absFen % 100 == 0) {
    body = _groupInt(yuan.round().toString());
  } else {
    final parts = yuan.toStringAsFixed(2).split('.');
    body = '${_groupInt(parts[0])}.${parts[1]}';
  }
  return '${negative ? '-' : ''}¥$body';
}

Map<TravelKind, int> travelKindCosts(List<TravelEmployee> people) {
  final map = {for (final k in TravelKind.values) k: 0};
  for (final p in people) {
    for (final l in p.legs) {
      map[l.kind] = (map[l.kind] ?? 0) + l.amount;
    }
  }
  return map;
}

String _rebookFeeKey(TravelEmployee person, TravelLeg leg) {
  final orderId = leg.orderId.trim();
  if (orderId.isNotEmpty) return orderId;
  return '${person.id}|${leg.kind.name}|${leg.date}|${leg.from}|${leg.to}|${leg.rebookFee}';
}

int travelRebookFeeFromLegs(String personId, List<TravelLeg> legs) {
  return travelRebookFeeTotal([
    TravelEmployee(
      id: personId,
      name: '',
      dept: '',
      cost: 0,
      trips: legs.length,
      lastTrip: '',
      provinces: const [],
      legs: legs,
    ),
  ]);
}

/// 手续费按订单去重。同行多行都带整单改签费，合计时只计一次。
int travelRebookFeeTotal(List<TravelEmployee> people) {
  final seen = <String>{};
  var sum = 0;
  for (final p in people) {
    for (final l in p.legs) {
      if (l.rebookFee <= 0) continue;
      if (seen.add(_rebookFeeKey(p, l))) sum += l.rebookFee;
    }
  }
  return sum;
}

Map<TravelKind, int> travelRebookFeeByKind(List<TravelEmployee> people) {
  final map = {for (final k in TravelKind.values) k: 0};
  final seen = <String>{};
  for (final p in people) {
    for (final l in p.legs) {
      if (l.rebookFee <= 0) continue;
      if (!seen.add(_rebookFeeKey(p, l))) continue;
      map[l.kind] = (map[l.kind] ?? 0) + l.rebookFee;
    }
  }
  return map;
}

List<TravelEmployee> employeesFor(List<TravelEmployee> all, String personId) {
  if (personId == 'all') return all;
  return all.where((e) => e.id == personId).toList();
}

bool legInDateRange(TravelLeg leg, DateTime? start, DateTime? end) {
  final d = DateTime.tryParse(leg.date);
  if (d == null) return true;
  final day = DateTime(d.year, d.month, d.day);
  if (start != null && day.isBefore(DateTime(start.year, start.month, start.day))) {
    return false;
  }
  if (end != null && day.isAfter(DateTime(end.year, end.month, end.day))) {
    return false;
  }
  return true;
}

List<TravelEmployee> filterTravelEmployees({
  required List<TravelEmployee> source,
  required String personId,
  required String nameQuery,
  DateTime? start,
  DateTime? end,
}) {
  var people = employeesFor(source, personId);
  final q = nameQuery.trim();
  if (q.isNotEmpty) {
    people = people
        .where((e) => e.name.contains(q) || e.dept.contains(q))
        .toList();
  }
  if (start == null && end == null) return people;

  final out = <TravelEmployee>[];
  for (final e in people) {
    final legs = e.legs.where((l) => legInDateRange(l, start, end)).toList();
    if (legs.isEmpty) continue;
    final cost = legs.fold<int>(0, (s, l) => s + l.amount);
    final provinces = <String>{};
    for (final l in legs) {
      provinces.addAll(provincesFromLegs([l]));
    }
    out.add(
      TravelEmployee(
        id: e.id,
        name: e.name,
        dept: e.dept,
        cost: cost,
        fee: travelRebookFeeFromLegs(e.id, legs),
        trips: legs.length,
        lastTrip: legs.map((l) => l.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b),
        provinces: provinces.toList(),
        legs: legs,
        provinceVisits: provinceStayCounts(legs),
      ),
    );
  }
  return out;
}

class TaggedLeg {
  const TaggedLeg({required this.person, required this.leg});
  final TravelEmployee person;
  final TravelLeg leg;
}

List<TaggedLeg> taggedLegs(
  List<TravelEmployee> people, {
  TravelKind? kind,
}) {
  final out = <TaggedLeg>[];
  for (final p in people) {
    for (final leg in p.legs) {
      if (kind != null && leg.kind != kind) continue;
      out.add(TaggedLeg(person: p, leg: leg));
    }
  }
  return out;
}

bool legTouchesProvince(TravelLeg leg, String province) {
  if (leg.kind == TravelKind.ground) {
    if (leg.originProvince == province) return true;
    return travelCityOf(leg.from)?.province == province;
  }
  if (leg.originProvince == province || leg.destProvince == province) return true;
  final a = travelCityOf(leg.from);
  final b = travelCityOf(leg.to);
  return a?.province == province || b?.province == province;
}

int provinceSpend(List<TaggedLeg> legs, String province) {
  var sum = 0;
  for (final item in legs) {
    if (legTouchesProvince(item.leg, province)) sum += item.leg.amount;
  }
  return sum;
}

String _legYmd(String raw) {
  final s = raw.trim();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _legProvince(TravelLeg leg, {required bool dest}) {
  final raw = dest ? leg.destProvince : leg.originProvince;
  if (raw.isNotEmpty) return raw;
  final city = travelCityOf(dest ? leg.to : leg.from);
  return city?.province ?? '';
}

/// 停留次数：酒店按所在省、机票/火车按到达省、用车按所在城市对应省；
/// 相邻不超过 2 天的日期合成一次。
Map<String, int> provinceStayCounts(List<TravelLeg> legs) {
  final days = <String, Set<String>>{};
  void add(String province, String day) {
    if (province.isEmpty || day.isEmpty) return;
    days.putIfAbsent(province, () => <String>{}).add(day);
  }

  for (final leg in legs) {
    final day = _legYmd(leg.date);
    switch (leg.kind) {
      case TravelKind.hotel:
        add(_legProvince(leg, dest: true), day);
        add(_legProvince(leg, dest: false), day);
      case TravelKind.flight || TravelKind.train:
        add(_legProvince(leg, dest: true), day);
      case TravelKind.ground:
        add(_legProvince(leg, dest: false), day);
    }
  }
  return {
    for (final e in days.entries) e.key: _clusterStayCount(e.value),
  };
}

int _clusterStayCount(Set<String> days) {
  if (days.isEmpty) return 0;
  final list = <DateTime>[];
  for (final d in days) {
    final t = DateTime.tryParse(d);
    if (t != null) list.add(t);
  }
  if (list.isEmpty) return 0;
  list.sort();
  var n = 1;
  var last = list.first;
  for (var i = 1; i < list.length; i++) {
    if (list[i].difference(last).inDays > 2) n++;
    last = list[i];
  }
  return n;
}

Map<String, double> provinceCostMap(List<TravelEmployee> people) {
  final map = <String, double>{};
  for (final p in people) {
    final share = p.cost / (p.provinces.isEmpty ? 1 : p.provinces.length);
    for (final name in p.provinces) {
      map[name] = (map[name] ?? 0) + share;
    }
  }
  return map;
}

bool routeIsPoint(TravelLeg leg) {
  if (leg.kind == TravelKind.hotel || leg.kind == TravelKind.ground) {
    return true;
  }
  if (leg.samePlace) return true;
  final a = travelCityOf(leg.from);
  final b = travelCityOf(leg.to);
  return a != null && b != null && a.name == b.name;
}
