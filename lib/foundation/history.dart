import 'dart:async';

import 'package:flutter/widgets.dart' show ChangeNotifier;
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/comic_type.dart';

import 'app.dart';

typedef HistoryType = ComicType;

abstract mixin class HistoryMixin {
  String get title;

  String? get subTitle;

  String get cover;

  String get id;

  int? get maxPage => null;

  HistoryType get historyType;
}

class History {
  HistoryType type;

  DateTime time;

  String title;

  String subtitle;

  String cover;
  
  int ep;

  int page;

  String id;

  Set<int> readEpisode;

  int? maxPage;

  History(this.type, this.time, this.title, this.subtitle, this.cover, this.ep,
      this.page, this.id,
      [this.readEpisode = const <int>{}, this.maxPage]);

  History.fromModel(
      {required HistoryMixin model,
      required this.ep,
      required this.page,
      this.readEpisode = const <int>{},
      DateTime? time})
      : type = model.historyType,
        title = model.title,
        subtitle = model.subTitle ?? '',
        cover = model.cover,
        id = model.id,
        time = time ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        "type": type.value,
        "time": time.millisecondsSinceEpoch,
        "title": title,
        "subtitle": subtitle,
        "cover": cover,
        "ep": ep,
        "page": page,
        "id": id,
        "readEpisode": readEpisode.toList(),
        "max_page": maxPage
      };

  History.fromMap(Map<String, dynamic> map)
      : type = HistoryType(map["type"]),
        time = DateTime.fromMillisecondsSinceEpoch(map["time"]),
        title = map["title"],
        subtitle = map["subtitle"],
        cover = map["cover"],
        ep = map["ep"],
        page = map["page"],
        id = map["id"],
        readEpisode = Set<int>.from(
            (map["readEpisode"] as List<dynamic>?)?.toSet() ?? const <int>{}),
        maxPage = map["max_page"];

  @override
  String toString() {
    return 'History{type: $type, time: $time, title: $title, subtitle: $subtitle, cover: $cover, ep: $ep, page: $page, id: $id}';
  }

  History.fromRow(Row row)
      : type = HistoryType(row["type"]),
        time = DateTime.fromMillisecondsSinceEpoch(row["time"]),
        title = row["title"],
        subtitle = row["subtitle"],
        cover = row["cover"],
        ep = row["ep"],
        page = row["page"],
        id = row["id"],
        readEpisode = Set<int>.from((row["readEpisode"] as String)
            .split(',')
            .where((element) => element != "")
            .map((e) => int.parse(e))),
        maxPage = row["max_page"];

  static Future<History> findOrCreate(
    HistoryMixin model, {
    int ep = 0,
    int page = 0,
  }) async {
    var history = await HistoryManager().find(model.id, model.historyType);
    if (history != null) {
      return history;
    }
    history = History.fromModel(model: model, ep: ep, page: page);
    HistoryManager().addHistory(history);
    return history;
  }

  static Future<History> createIfNull(
      History? history, HistoryMixin model) async {
    if (history != null) {
      return history;
    }
    history = History.fromModel(model: model, ep: 0, page: 0);
    HistoryManager().addHistory(history);
    return history;
  }
}

class HistoryManager with ChangeNotifier {
  static HistoryManager? cache;

  HistoryManager.create();

  factory HistoryManager() =>
      cache == null ? (cache = HistoryManager.create()) : cache!;

  late Database _db;

  int get length => _db.select("select count(*) from history;").first[0] as int;

  Map<String, bool>? _cachedHistory;

  Future<void> init() async {
    _db = sqlite3.open("${App.dataPath}/history.db");

    _db.execute("""
        create table if not exists history  (
          id text primary key,
          title text,
          subtitle text,
          cover text,
          time int,
          type int,
          ep int,
          page int,
          readEpisode text,
          max_page int
        );
      """);
  }

  /// add history. if exists, update time.
  ///
  /// This function would be called when user start reading.
  Future<void> addHistory(History newItem) async {
    var res = _db.select("""
      select * from history
      where id == ? and type == ?;
    """, [newItem.id, newItem.type.value]);
    if (res.isEmpty) {
      _db.execute("""
        insert into history (id, title, subtitle, cover, time, type, ep, page, readEpisode, max_page)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """, [
        newItem.id,
        newItem.title,
        newItem.subtitle,
        newItem.cover,
        newItem.time.millisecondsSinceEpoch,
        newItem.type.value,
        newItem.ep,
        newItem.page,
        newItem.readEpisode.join(','),
        newItem.maxPage
      ]);
    } else {
      _db.execute("""
        update history
        set time = ${DateTime.now().millisecondsSinceEpoch}
        where id == ? and type == ?;
      """, [newItem.id, newItem.type.value]);
    }
    updateCache();
    notifyListeners();
  }

  Future<void> saveReadHistory(History history) async {
    _db.execute("""
        update history
        set time = ${DateTime.now().millisecondsSinceEpoch}, ep = ?, page = ?, readEpisode = ?, max_page = ?
        where id == ? and type == ?;
    """, [
      history.ep,
      history.page,
      history.readEpisode.join(','),
      history.maxPage,
      history.id,
      history.type.value
    ]);
    notifyListeners();
  }

  void clearHistory() {
    _db.execute("delete from history;");
    updateCache();
  }

  void remove(String id, ComicType type) async {
    _db.execute("""
      delete from history
      where id == ? and type == ?;
    """, [id, type.value]);
    updateCache();
  }

  Future<History?> find(String id, ComicType type) async {
    return findSync(id, type);
  }

  void updateCache() {
    _cachedHistory = {};
    var res = _db.select("""
        select * from history;
      """);
    for (var element in res) {
      _cachedHistory![element["id"] as String] = true;
    }
  }

  History? findSync(String id, ComicType type) {
    if(_cachedHistory == null) {
      updateCache();
    }
    if (!_cachedHistory!.containsKey(id)) {
      return null;
    }

    var res = _db.select("""
      select * from history
      where id == ? and type == ?;
    """, [id, type.value]);
    if (res.isEmpty) {
      return null;
    }
    return History.fromRow(res.first);
  }

  List<History> getAll() {
    var res = _db.select("""
      select * from history
      order by time DESC;
    """);
    return res.map((element) => History.fromRow(element)).toList();
  }

  /// 获取最近阅读的漫画
  List<History> getRecent() {
    var res = _db.select("""
      select * from history
      order by time DESC
      limit 20;
    """);
    return res.map((element) => History.fromRow(element)).toList();
  }

  /// 获取历史记录的数量
  int count() {
    var res = _db.select("""
      select count(*) from history;
    """);
    return res.first[0] as int;
  }
}
