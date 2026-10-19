/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.value;
/// 行与 Json 之间的小工具。行的类型就一种：`Json[string]`（列 key → 值），
/// 没有实体对象，所以取值只在「某个键在不在」这一层。

import vibe.data.json : Json;

import std.bigint : BigInt;
import std.conv : to;

/// 一行：列 key → 已按列类型转好的 Json。
alias Row = Json[string];

/// 空行：`Row.init` 写在这，别处别再写 `Json[string].init`（db.d 里 `Row` 会被结果行类型抢走）。
Row emptyRow() {
  return Row.init;
}

/// 安全取值：不存在的键返回 undefined（**不用 `opIndex`**——它会把键插进对象里）。
Json jsonGet(Json obj, string key) {
  if (auto pv = key in obj)
    return *pv;
  return Json.undefined;
}

/// 行取值：不存在的列返回 undefined。
Json rowGet(Row row, string key) {
  if (auto pv = key in row)
    return *pv;
  return Json.undefined;
}

/// 值转字符串（派生属性模板、关系 id 都用它）。
string jsonText(Json value) {
  final switch (value.type) {
  case Json.Type.undefined:
  case Json.Type.null_:
    return "";
  case Json.Type.string:
    return value.get!string;
  case Json.Type.bool_:
    return value.get!bool ? "true" : "false";
  case Json.Type.int_:
    return value.get!long.to!string;
  case Json.Type.float_:
    return value.get!double.to!string;
  case Json.Type.bigInt:
    return value.get!BigInt.to!string;
  case Json.Type.array:
  case Json.Type.object:
    return value.toString();
  }
}

/// 是否为空（undefined / null 都算）。
bool isBlank(Json value) {
  return value.type == Json.Type.undefined || value.type == Json.Type.null_;
}
