/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data.dao.pq;
/// 最小 libpq 绑定：只覆盖 DAO 需要的连接、参数化查询和文本结果集。
///
/// 不引入 ORM 或第三方 PostgreSQL 驱动。所有参数都按文本发送，结果也按文本读取，
/// 与现有 DAO 的 Json 行模型一致；结果对象的析构负责调用 PQclear。

import std.string : fromStringz, toStringz;

alias PGconn = void;
alias PGresult = void;

private enum int connectionOk = 0;
private enum int commandOk = 1;
private enum int tuplesOk = 2;

extern(C) {
  PGconn* PQconnectdb(const(char)* conninfo);
  int PQstatus(const PGconn* conn);
  char* PQerrorMessage(const PGconn* conn);
  void PQfinish(PGconn* conn);

  PGresult* PQexecParams(PGconn* conn, const(char)* command, int nParams,
      const(int)* paramTypes, const(char)** paramValues, const(int)* paramLengths,
      const(int)* paramFormats, int resultFormat);
  int PQresultStatus(const PGresult* result);
  char* PQresultErrorMessage(const PGresult* result);
  void PQclear(PGresult* result);
  int PQntuples(const PGresult* result);
  int PQnfields(const PGresult* result);
  int PQfnumber(const PGresult* result, const(char)* fieldName);
  int PQgetisnull(const PGresult* result, int row, int column);
  char* PQgetvalue(const PGresult* result, int row, int column);
  int PQgetlength(const PGresult* result, int row, int column);
}

/// 连接失败或查询失败。DAO 会把它转换成 DaoException 并保留原始 libpq 文本。
class PgException : Exception {
  this(string msg, string file = __FILE__, size_t line = __LINE__) @safe {
    super(msg, file, line);
  }
}

/// 一个查询结果。行按需读取，不把整个结果复制到 GC 堆。
struct PgResult {
  private PGresult* result;
  private size_t rowCount;

  this(PGresult* result) {
    this.result = result;
    this.rowCount = result is null ? 0 : PQntuples(result);
  }

  ~this() {
    if (result !is null)
      PQclear(result);
  }

  @disable this(this);

  size_t length() const {
    return rowCount;
  }

  bool empty() const {
    return rowCount == 0;
  }

  PgRow opIndex(size_t row) {
    if (row >= rowCount)
      throw new PgException("postgres row index out of range");
    return PgRow(result, row);
  }

  int opApply(scope int delegate(PgRow) dg) {
    foreach (i; 0 .. rowCount) {
      auto ret = dg(PgRow(result, i));
      if (ret)
        return ret;
    }
    return 0;
  }
}

/// 结果集里的一行；按列序号或列名取值。
struct PgRow {
  private PGresult* result;
  private size_t row;

  PgValue opIndex(size_t column) {
    return PgValue(result, row, column);
  }

  PgValue opIndex(string column) {
    auto index = PQfnumber(result, toStringz(column));
    if (index < 0)
      throw new PgException("postgres column not found: " ~ column);
    return PgValue(result, row, cast(size_t) index);
  }
}

/// 一个文本列值；`isNull` 区分数据库 NULL 与空字符串。
struct PgValue {
  private PGresult* result;
  private size_t row;
  private size_t column;

  bool isNull() const {
    return result is null || PQgetisnull(result, cast(int) row, cast(int) column) != 0;
  }

  string toString() const {
    if (isNull())
      return "";
    auto value = PQgetvalue(result, cast(int) row, cast(int) column);
    auto length = PQgetlength(result, cast(int) row, cast(int) column);
    return value is null || length <= 0 ? "" : value[0 .. length].idup;
  }
}

/// 打开连接；失败时抛出带 `PQerrorMessage` 的异常。
PGconn* open(string connInfo) {
  auto conn = PQconnectdb(toStringz(connInfo));
  if (conn is null)
    throw new PgException("postgres connection returned null");
  if (PQstatus(conn) != connectionOk) {
    auto message = errorMessage(conn);
    PQfinish(conn);
    throw new PgException("postgres connection failed: " ~ message);
  }
  return conn;
}

/// 关闭连接；重复调用安全。
void close(ref PGconn* conn) {
  if (conn !is null) {
    PQfinish(conn);
    conn = null;
  }
}

/// 执行一条参数化 SQL。参数只支持文本格式；`null` 参数会以 SQL NULL 发送。
PgResult exec(PGconn* conn, string sql, const(string)[] args) {
  if (conn is null)
    throw new PgException("postgres connection is closed");

  const(char)*[] values;
  values.reserve(args.length);
  foreach (arg; args)
    values ~= arg is null ? null : toStringz(arg);

  auto result = PQexecParams(conn, toStringz(sql), cast(int) values.length,
      null, values.length == 0 ? null : values.ptr, null, null, 0);
  if (result is null)
    throw new PgException("postgres query failed: " ~ errorMessage(conn));

  auto status = PQresultStatus(result);
  if (status != tuplesOk && status != commandOk) {
    auto message = resultErrorMessage(result);
    PQclear(result);
    throw new PgException(message.length == 0 ? "postgres query failed" : message);
  }
  return PgResult(result);
}

private string errorMessage(PGconn* conn) {
  auto message = conn is null ? null : PQerrorMessage(conn);
  return message is null ? "" : fromStringz(message).idup;
}

private string resultErrorMessage(PGresult* result) {
  auto message = result is null ? null : PQresultErrorMessage(result);
  return message is null ? "" : fromStringz(message).idup;
}
