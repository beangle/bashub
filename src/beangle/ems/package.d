/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module beangle.ems;
/// 进程可见的 ems 常量（scala `object Ems` 的常量子集）：base/cas/api/key/sid/hostname。
/// security 侧要的量都在这里——会话 cookie 名（`sid.name`）、cas 地址、`inner_base` 推导出来的
/// 内网 api——宿主不必再抄一遍，抄错一份就是「拿不到会话」这种最难查的故障。
///
/// 没移植的部分（README 的裁剪清单里也记着）：`decryptor`（PBE 加解密）、`resources.xml`、
/// `Ems key plain` 那条命令行、以及 `Org`/`Domain`/`Theme` 这几个纯数据类。

import beangle.ems.env : EmsEnv, findHome, innerEnv, loadEnv, processEnv, readConfig;

import std.algorithm.searching : endsWith;
import std.base64 : Base64URLNoPadding;
import std.digest : toHexString;
import std.digest.md : md5Of;
import std.random : unpredictableSeed;
import std.string : indexOf, toLower;

/// 会话 cookie 的名字与前缀（scala `Ems.Sid`）：security 侧靠它找会话，所以别在别处硬编码。
struct Sid {
  string name;
  string prefix;
}

/// scala `Sid.apply(properties)`
Sid sidOf(string[string] properties) {
  Sid sid;
  sid.name = properties.get("session_id_name", "EMS_SID");
  sid.prefix = properties.get("session_id_prefix", "EMS-");
  return sid;
}

/// 一套 ems 常量。`env` 是对外那套地址，`innerEnvironment` 是配了 `inner_base` 的内网那套
/// （scala `object Ems` 里那个 private 的 `innerEnv`）。
class Ems {
  EmsEnv env;
  EmsEnv innerEnvironment;
  /// scala 里是 `var`（能改），这里也留着可改——不过改了就等于换了一套部署
  Sid sid;

  this(EmsEnv env) {
    this.env = env;
    this.innerEnvironment = innerEnv(env);
    this.sid = sidOf(env.properties);
  }

  string base() { return env.base; }
  string profile() { return env.profile; }
  string cas() { return env.cas; }
  string portal() { return env.portal; }
  string index() { return env.index; }
  string api() { return env.api; }
  string blob() { return env.blob; }
  string webapp() { return env.webapp; }
  string staticUrl() { return env.staticUrl; }
  string key() { return env.key; }
  string[string] properties() { return env.properties; }

  /// 内网 api（scala `Ems.innerApi`）：没配 `inner_base` 时与 `api` 同值
  string innerApi() { return innerEnvironment.api; }

  /// 从 base 里取主机名（scala `Ems.hostname`：`://` 之后、第一个 `/` 之前）
  string hostname() {
    auto h = base;
    auto schemeEnd = h.indexOf("://");
    h = (schemeEnd < 0) ? "" : h[schemeEnd + 3 .. $];
    auto slash = h.indexOf('/');
    return (slash < 0) ? h : h[0 .. slash];
  }

  /// 这个 contextPath 是不是「平台自带」的几处（cas / api+`/platform` / portal 的结尾，scala `Ems.isPlatform`）
  bool isPlatform(string contextPath) {
    return cas.endsWith(contextPath) || (api ~ "/platform").endsWith(contextPath) || portal.endsWith(contextPath);
  }

  /// 门户上的头像地址 `/platform/user/avatars/<md5(userCode)>`（scala `Ems.avatarUrl`）
  string avatarUrl(string userCode) {
    return api ~ "/platform/user/avatars/" ~ md5Hex(userCode);
  }

  /// 32 字节随机 → base64url 无 padding（scala `Ems.generateKey`，用在「重置通道凭证」）。
  /// D 没有 `SecureRandom`，用 `std.random.unpredictableSeed`：Linux 上它走 `getrandom(2)`，
  /// 与 `SecureRandom` 同源；但标准库**不承诺**它是密码学安全的，所以别拿它当长期密钥。
  static string generateKey() {
    ubyte[32] bytes;
    size_t offset = 0;
    while (offset < bytes.length) {
      auto seed = unpredictableSeed!ulong;
      foreach (j; 0 .. 8)
        bytes[offset + j] = cast(ubyte) (seed >> (j * 8));
      offset += 8;
    }
    return Base64URLNoPadding.encode(bytes[]).idup;
  }
}

/// 按 home 与 `conf.properties` 建一个 Ems（scala `object Ems` 的字段初始化那两行）
Ems loadEms(string home, string[string] properties) {
  return new Ems(loadEnv(home, properties));
}

/** 按环境变量建 Ems；`ems.home`/`ems.base`/`ems.profile` 一个都没配就返回 null。
 *
 * 返回 null 而不是「凭空造一套缺省」：宿主没跑在 ems 部署下时，不该被悄悄换掉缺省行为。
 */
Ems emsFromEnvironment(string[string] vars = null) {
  if (vars is null)
    vars = processEnv();
  if (!hasValue(vars, "ems.home") && !hasValue(vars, "ems.base") && !hasValue(vars, "ems.profile"))
    return null;
  auto home = findHome(vars);
  return loadEms(home, readConfig(home));
}

private bool hasValue(string[string] vars, string name) {
  auto v = vars.get(name, null);
  return v !is null && v.length > 0;
}

/// md5 的小写十六进制（scala `Digests.md5Hex`）；头像 URL 与配置摘要用它
string md5Hex(string text) {
  auto digest = md5Of(text);
  return toHexString(digest[]).toLower;
}
