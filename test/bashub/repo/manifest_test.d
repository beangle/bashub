/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.repo.manifest_test;

import bashub.repo.manifest : WarCoordinates, readWarCoordinates, repositoryPath;

import test.beangle.tempdir : uniqueTempDir;

import std.file : rmdirRecurse, write;
import std.path : buildPath;
import std.zip : ArchiveMember, ZipArchive;

@("war coordinates come from MANIFEST.MF Implementation-* attributes")
unittest {
  auto dir = uniqueTempDir("bashub-war-manifest-");
  scope (exit) rmdirRecurse(dir);
  auto war = buildPath(dir, "portal-4.20.13.war");
  write(war, archiveWithManifest(
      "Manifest-Version: 1.0\r\n" ~
      "Implementation-Vendor-Id: org.beangle\r\n" ~
      "Implementation-Title: beangle-ems-portal\r\n" ~
      "Implementation-Version: 4.20.13\r\n\r\n"));

  WarCoordinates coords;
  string error;
  assert(readWarCoordinates(war, coords, error), error);
  assert(coords.groupId == "org.beangle");
  assert(coords.artifactId == "beangle-ems-portal");
  assert(coords.artifactVersion == "4.20.13");
  assert(repositoryPath(coords, "portal-4.20.13.war") ==
      "org/beangle/beangle-ems-portal/4.20.13/portal-4.20.13.war");
}

@("missing manifest or implementation attributes are rejected")
unittest {
  auto dir = uniqueTempDir("bashub-war-invalid-");
  scope (exit) rmdirRecurse(dir);

  auto noManifest = buildPath(dir, "plain.war");
  auto zip = new ZipArchive();
  auto entry = new ArchiveMember();
  entry.name = "WEB-INF/web.xml";
  entry.expandedData = cast(ubyte[]) "<web-app/>".dup;
  zip.addMember(entry);
  write(noManifest, zip.build());

  WarCoordinates coords;
  string error;
  assert(!readWarCoordinates(noManifest, coords, error));
  assert(error == "上传的文件中没有找到 MANIFEST.MF");

  auto incomplete = buildPath(dir, "incomplete.war");
  write(incomplete, archiveWithManifest("Manifest-Version: 1.0\r\n\r\n"));
  assert(!readWarCoordinates(incomplete, coords, error));
  assert(error.length > 0);
}

private void[] archiveWithManifest(string manifest) {
  auto entry = new ArchiveMember();
  entry.name = "META-INF/MANIFEST.MF";
  entry.expandedData = cast(ubyte[]) manifest.dup;
  auto zip = new ZipArchive();
  zip.addMember(entry);
  return zip.build();
}
