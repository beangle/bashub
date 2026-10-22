/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.agent.socket_test;
/// 流控只由 hub 决定：这里只测采样窗口与到点判断，不依赖真 WebSocket。

import bashub.agent.channel : Envelope, parse, reportHealth;
import bashub.agent.socket : HealthSchedule;

import core.time : minutes, seconds;
import std.datetime : DateTime, LocalTime, SysTime;

private SysTime at(int hour, int minute) {
  return SysTime(DateTime(2026, 10, 22, hour, minute), LocalTime());
}

@("health schedule honors the interval and daytime window") unittest {
  auto health = HealthSchedule(300, 7 * 60, 22 * 60);
  assert(!health.due(at(6, 59), 5.minutes));
  assert(!health.due(at(7, 0), 5.minutes - 1.seconds));
  assert(health.due(at(7, 0), 5.minutes));
  assert(health.due(at(21, 59), 5.minutes));
  assert(!health.due(at(22, 0), 5.minutes));
}

@("health schedule supports a window across midnight") unittest {
  auto health = HealthSchedule(600, 22 * 60, 7 * 60);
  assert(health.due(at(22, 0), 10.minutes));
  assert(health.due(at(0, 0), 10.minutes));
  assert(health.due(at(6, 59), 10.minutes));
  assert(!health.due(at(7, 0), 10.minutes));
}

@("health schedule can be disabled") unittest {
  auto health = HealthSchedule(0, 7 * 60, 22 * 60);
  assert(!health.enabled);
  assert(!health.due(at(12, 0), 24.minutes));
}

@("hub health trigger is a notification without an id") unittest {
  Envelope message;
  assert(parse(reportHealth(), message));
  assert(message.typ == "report:health");
  assert(!message.id.length);
}
