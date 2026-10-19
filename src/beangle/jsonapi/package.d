/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.jsonapi;
/// JSON:API 协议面：请求参数 → 数据面查询 → 文档（data/included/meta.page/errors）→ HTTP 响应。
/// 只放「与协议有关」的东西；行、资源映射、查询计划、SQL、Dao 都在 `beangle.data` 里。
