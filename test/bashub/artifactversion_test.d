/* Copyright (C) 2026 Beangle
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

module test.bashub.artifactversion_test;

import bashub.artifactversion : ArtifactMetadataLoader, artifactMetadataUrl, latestFromMetadata,
  refreshAllArtifactVersions, refreshArtifactVersions;

import beangle.data.dao.memory : MemoryDao;
import beangle.data.resource : Column, Kind, Registry, Resource;
import beangle.data.value : Row, jsonText, rowGet;
import beangle.jsonapi.store : Store;

import vibe.data.json : Json;

import std.string : endsWith;

@("maven metadata latest version is read from versioning/latest")
unittest {
  auto xml = `<?xml version="1.0" encoding="UTF-8"?>
    <metadata>
      <groupId>org.beangle</groupId>
      <artifactId>beangle-webmvc</artifactId>
      <versioning>
        <latest>4.6.0</latest>
        <release>4.6.0</release>
      </versioning>
    </metadata>`;
  assert(latestFromMetadata(xml) == "4.6.0");
  assert(latestFromMetadata("<metadata/>") == "");
}

@("artifact metadata url follows the maven repository layout")
unittest {
  assert(artifactMetadataUrl("org.beangle", "beangle-webmvc") ==
      "https://repo1.maven.org/maven2/org/beangle/beangle-webmvc/maven-metadata.xml");
}

@("refresh updates changed versions and skips failures or unchanged rows")
unittest {
  auto reg = new Registry([
    Resource(
      "artifacts", "artifacts", "bas.cfg_artifacts", "id",
      [
        Column("group_id", "groupId", Kind.text),
        Column("artifact_id", "artifactId", Kind.text),
        Column("latest_version", "latestVersion", Kind.text),
      ],
      [], [], "id")
  ]);
  auto dao = new MemoryDao(reg);
  auto artifacts = reg.find("artifacts");
  dao.seed(artifacts, artifactRow("3001", "org.beangle", "beangle-webmvc", "4.5.0"));
  dao.seed(artifacts, artifactRow("3002", "org.beangle", "missing", "1.0.0"));
  dao.seed(artifacts, artifactRow("3003", "org.beangle", "unchanged", "2.0.0"));
  auto store = new Store(reg, dao);

  string[] requested;
  ArtifactMetadataLoader loader = (string url) {
    requested ~= url;
    if (url.endsWith("/beangle-webmvc/maven-metadata.xml"))
      return `<metadata><versioning><latest>4.6.0</latest></versioning></metadata>`;
    if (url.endsWith("/unchanged/maven-metadata.xml"))
      return `<metadata><versioning><latest>2.0.0</latest></versioning></metadata>`;
    return "";
  };

  assert(refreshArtifactVersions(reg, store, ["3001", "3002", "3003"], loader) == 1);
  assert(requested.length == 3);
  assert(jsonText(rowGet(dao.findById(artifacts, "3001"), "latest_version")) == "4.6.0");
  assert(jsonText(rowGet(dao.findById(artifacts, "3002"), "latest_version")) == "1.0.0");
  assert(jsonText(rowGet(dao.findById(artifacts, "3003"), "latest_version")) == "2.0.0");
}

@("refresh all scans the unpaged artifact list")
unittest {
  auto reg = new Registry([
    Resource(
      "artifacts", "artifacts", "bas.cfg_artifacts", "id",
      [
        Column("group_id", "groupId", Kind.text),
        Column("artifact_id", "artifactId", Kind.text),
        Column("latest_version", "latestVersion", Kind.text),
      ],
      [], [], "id")
  ]);
  auto dao = new MemoryDao(reg);
  auto artifacts = reg.find("artifacts");
  dao.seed(artifacts, artifactRow("3101", "org.beangle", "beangle-commons", "5.0.0"));
  auto store = new Store(reg, dao);

  ArtifactMetadataLoader loader = (string url) {
    return `<metadata><versioning><latest>5.1.0</latest></versioning></metadata>`;
  };
  assert(refreshAllArtifactVersions(reg, store, loader) == 1);
  assert(jsonText(rowGet(dao.findById(artifacts, "3101"), "latest_version")) == "5.1.0");
}

private Row artifactRow(string id, string groupId, string artifactId, string latestVersion) {
  Row row;
  row["id"] = Json(id);
  row["group_id"] = Json(groupId);
  row["artifact_id"] = Json(artifactId);
  row["latest_version"] = Json(latestVersion);
  return row;
}
