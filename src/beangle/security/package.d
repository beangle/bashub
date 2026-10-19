/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.security;
/// 安全域·会话面：会话/账户/终端模型、`SessionRepo` 契约、内存缓存与会话服务客户端。
/// 对应 scala 侧的 `org.beangle.security.session.*` 与 `org.beangle.ems.app.cas.CasHttpSessionRepo`，
/// 只保留控制台用得到的字段与动作；时间统一用 epoch 秒（心跳 URL 用这个单位，报文是 ISO 文本）。
///
/// 这里**不含**登录流程：票据校验、302 跳转、单点登出都在网关/CAS 侧，本包只读写「会话数据」。
