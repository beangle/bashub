/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.beangle.security.fake_cas;
/// 测试用的假 CAS：一个线程里的极简 HTTP/1.1 服务，只做「按路径回一段字节」这一件事。
///
/// 为什么不用 vibe 的 `listenHTTP`：`CasSessionRepo` 默认的 HTTP 客户端是**阻塞的 curl 子进程**，
/// 同一个事件循环里既跑服务端又跑 curl 会互相等（死锁）。所以服务端放独立线程、用裸 socket，
/// 这样测的就是真链路（URL 拼装 → curl → 真 TCP → 响应解析 → JSON 解码）。

import core.sync.mutex : Mutex;
import core.thread : Thread;
import core.time : msecs;

import std.conv : to;
import std.socket;
import std.string : indexOf, split, strip;

class FakeCas {
  /// 完整请求路径（含 query）→ 响应状态与响应体
  private int[string] statusOf;
  private ubyte[][string] bodyOf;
  /// 按序记下收到的请求路径，供测试断言「URL 拼得对不对」
  private string[] history;
  private Mutex lock;

  private Socket listener;
  private Thread worker;
  private bool running;

  this() {
    lock = new Mutex();
  }

  /// 装一条路由；`path` 是含 query 的完整路径（如 `/session/a?format=application/json`）。
  void on(string path, int status, ubyte[] body) {
    synchronized (lock) {
      statusOf[path] = status;
      bodyOf[path] = body;
    }
  }

  /// 起监听，返回内核分配的真实端口。
  ushort start() {
    listener = new TcpSocket(AddressFamily.INET);
    listener.bind(new InternetAddress("127.0.0.1", 0));
    listener.listen(16);
    running = true;
    worker = new Thread(&serve);
    worker.start();
    return (cast(InternetAddress) listener.localAddress).port;
  }

  void stop() {
    running = false;
    if (worker !is null) {
      worker.join(); // serve 每轮只 select 最多 100ms，所以这里最多等一小会儿
      worker = null;
    }
    if (listener !is null) {
      listener.close();
      listener = null;
    }
  }

  /// 到目前为止收到过的请求路径（按序）。
  string[] requests() {
    synchronized (lock)
      return history.dup;
  }

  private void serve() {
    while (running) {
      auto set = new SocketSet();
      set.add(listener);
      if (Socket.select(set, null, null, 100.msecs) == 0)
        continue;
      Socket client;
      try {
        client = listener.accept();
      } catch (SocketException e) {
        continue;
      }
      scope (exit) {
        if (client !is null)
          client.close();
      }
      handle(client);
    }
  }

  private void handle(Socket client) {
    auto buf = new ubyte[8192];
    size_t total;
    while (total < buf.length) {
      auto n = client.receive(buf[total .. $]);
      if (n <= 0)
        return;
      total += n;
      if ((cast(string) buf[0 .. total]).indexOf("\r\n\r\n") >= 0)
        break;
    }
    auto head = (cast(string) buf[0 .. total]).split("\r\n")[0];
    auto parts = head.split(" ");
    if (parts.length < 2)
      return;
    auto path = parts[1].strip;

    int status;
    ubyte[] body;
    synchronized (lock) {
      history ~= path;
      status = (path in statusOf) ? statusOf[path] : 404;
      if (auto found = path in bodyOf)
        body = (*found).dup;
    }

    // Content-Type 只是让报文合法：客户端按 URL 上的 format 选解码器，不看这个头
    auto head2 = "HTTP/1.1 " ~ status.to!string ~ " " ~ (status == 200 ? "OK" : "Not Found") ~ "\r\n"
        ~ "Content-Type: application/json\r\n"
        ~ "Content-Length: " ~ body.length.to!string ~ "\r\n"
        ~ "Connection: close\r\n\r\n";
    sendAll(client, cast(const(ubyte)[]) head2);
    sendAll(client, body);
  }

  private void sendAll(Socket client, const(ubyte)[] data) {
    size_t sent;
    while (sent < data.length) {
      auto n = client.send(data[sent .. $]);
      if (n <= 0)
        return;
      sent += n;
    }
  }
}
