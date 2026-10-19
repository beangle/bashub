/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.data.query_test;
/// 查询参数解析：这套参数名/优先级是前端 EmsJsonApiClient 与 she 的 QueryHelper 的共同契约。

import beangle.data.query;

import std.conv : to;
import std.exception : assertThrown;

private FilterClause clause(Query q, string key) {
  foreach (f; q.filters) {
    if (f.key == key)
      return f;
  }
  assert(0, "missing filter: " ~ key);
}

@("parse page/sort/filter/include")
unittest {
  // 字符串键里带 `[]`，正是 EmsJsonApiClient 发出来的形状
  auto params = [
    "page[number]": "2", "page[size]": "5", "sort": "-name,title",
    "filter[name]": "abc", "filter[org.name]": "beangle", "include": "org,platform",
  ];
  auto q = parseQuery(params);
  assert(q.pageNumber == 2);
  assert(q.pageSize == 5);
  assert(q.sorts.length == 2);
  assert(q.sorts[0].field == "name" && q.sorts[0].desc);
  assert(q.sorts[1].field == "title" && !q.sorts[1].desc);
  assert(clause(q, "name").value == "abc");
  assert(clause(q, "org.name").value == "beangle");
  assert(q.includes == ["org", "platform"]);
}

@("repeated filters and explicit operators keep every value")
unittest {
  auto q = parseQuery([
    QueryParam("filter[name]", "beangle"),
    QueryParam("filter[name]", "openurp"),
    QueryParam("filter[httpPort][ge]", "8080"),
    QueryParam("filter[name][in]", "a,b;c，d；e"),
  ]);
  assert(q.filters.length == 3, "filters=" ~ q.filters.length.to!string);
  assert(q.filters[0].key == "name" && q.filters[0].op.length == 0);
  assert(q.filters[0].value == "beangle,openurp");
  assert(q.filters[1].key == "httpPort" && q.filters[1].op == "ge");
  assert(q.filters[2].key == "name" && q.filters[2].op == "in");
  assert(q.filters[2].value == "a,b;c，d；e");
}

@("orderBy wins over sort, pageIndex wins over page[number]")
unittest {
  auto q = parseQuery(["sort": "name", "orderBy": "-title", "pageIndex": "3", "pageNumber": "9",
      "page[number]": "8", "pageSize": "7", "page[size]": "6"]);
  assert(q.sorts.length == 1 && q.sorts[0].field == "title" && q.sorts[0].desc);
  assert(q.pageNumber == 3);
  assert(q.pageSize == 7);
}

@("defaults follow Page.DefaultPageNo/Size")
unittest {
  auto q = parseQuery(["filter[title]": "x"]);
  assert(q.pageNumber == 1);
  assert(q.pageSize == 20);
  // 空 filter 值不成为条件（空白过滤参数在 Scala 侧也是丢掉）
  assert(parseQuery(["filter[name]": ""]).filters.length == 0);
}

@("cookie pageSize is only a fallback")
unittest {
  assert(parseQuery([], "50").pageSize == 50);
  assert(parseQuery(["page[size]": "5"], "50").pageSize == 5);
  assert(parseQuery(["pageSize": "7"], "50").pageSize == 7);
  auto q = parseQuery([QueryParam("pageSize", "7")], "50");
  assert(q.pageSize == 7);
}

@("illegal or non-positive page params")
unittest {
  assertThrown!QueryException(parseQuery(["page[number]": "abc"]));
  // 小于 1 与 QueryHelper 一致：回落缺省，而不是报错
  auto q = parseQuery(["page[number]": "0", "page[size]": "-3"]);
  assert(q.pageNumber == 1);
  assert(q.pageSize == 20);
}
