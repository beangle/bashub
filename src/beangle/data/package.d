/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.data;
/// 数据面：把「表 + 列/关系映射」当成资源，直接拼 SQL 取行，不关心请求/响应的形状。
/// 只有行（`Row`）与计划（`Plan`），没有实体对象、没有会话、没有一二级缓存。
///
/// 协议面（JSON:API 的文档与路由）在 `beangle.jsonapi`：它依赖本包，本包不依赖它。
